defmodule Blackboex.Organizations do
  @moduledoc """
  The Organizations context. Manages organizations, memberships, and multi-tenancy.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Accounts
  alias Blackboex.Accounts.User
  alias Blackboex.Audit

  alias Blackboex.Organizations.{
    Invitation,
    Membership,
    Organization,
    OrganizationQueries,
    OrgInvitationNotifier
  }

  alias Blackboex.Projects.Samples
  alias Blackboex.Repo
  alias Ecto.Multi

  @spec create_organization(User.t(), map(), keyword()) ::
          {:ok, %{organization: Organization.t(), membership: Membership.t()}}
          | {:error, atom(), Ecto.Changeset.t(), map()}
  def create_organization(%User{} = user, attrs, opts \\ []) do
    samples_opts = Keyword.take(opts, [:materialize])

    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
    |> Multi.insert(:membership, fn %{organization: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: org.id,
        role: :owner
      })
    end)
    |> Multi.run(:sample_workspace, fn _repo, %{organization: org} ->
      Samples.provision_for_org(org, user, samples_opts)
    end)
    |> Multi.run(:project, fn _repo, %{sample_workspace: %{project: project}} ->
      {:ok, project}
    end)
    |> Multi.run(:project_membership, fn _repo, %{sample_workspace: %{membership: membership}} ->
      {:ok, membership}
    end)
    |> Repo.transaction()
  end

  @spec list_user_organizations(User.t()) :: [Organization.t()]
  def list_user_organizations(%User{} = user) do
    user.id
    |> OrganizationQueries.for_user()
    |> Repo.all()
  end

  @spec get_organization!(Ecto.UUID.t()) :: Organization.t()
  def get_organization!(id) do
    Repo.get!(Organization, id)
  end

  @spec get_organization(Ecto.UUID.t()) :: Organization.t() | nil
  def get_organization(id) do
    Repo.get(Organization, id)
  end

  @spec get_organization_by_slug(String.t()) :: Organization.t() | nil
  def get_organization_by_slug(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @spec update_organization(Organization.t(), map()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @spec add_member(Organization.t(), User.t(), atom()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def add_member(%Organization{} = org, %User{} = user, role) do
    case %Membership{}
         |> Membership.changeset(%{
           user_id: user.id,
           organization_id: org.id,
           role: role
         })
         |> Repo.insert() do
      {:ok, membership} ->
        Audit.log_async("member.added", %{
          resource_type: "membership",
          resource_id: membership.id,
          organization_id: org.id,
          user_id: user.id
        })

        {:ok, membership}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec remove_member(Organization.t(), Membership.t()) ::
          {:ok, Membership.t()} | {:error, :last_owner}
  def remove_member(%Organization{} = org, %Membership{role: :owner} = membership) do
    import Ecto.Query, warn: false

    owner_count =
      Membership
      |> where([m], m.organization_id == ^org.id and m.role == :owner)
      |> Repo.aggregate(:count)

    if owner_count <= 1 do
      {:error, :last_owner}
    else
      Repo.delete(membership)
    end
  end

  def remove_member(%Organization{}, %Membership{} = membership) do
    Repo.delete(membership)
  end

  @spec update_member_role(Membership.t(), atom()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def update_member_role(%Membership{} = membership, role) do
    membership
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  @spec get_user_membership(Organization.t(), User.t()) :: Membership.t() | nil
  def get_user_membership(%Organization{} = org, %User{} = user) do
    Repo.get_by(Membership, user_id: user.id, organization_id: org.id)
  end

  @spec list_memberships(Organization.t()) :: [Membership.t()]
  def list_memberships(%Organization{} = org) do
    import Ecto.Query, warn: false

    Membership
    |> where([m], m.organization_id == ^org.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Returns the plan of the user's first organization.
  Used by FunWithFlags.Group protocol for plan-based feature gating.
  """
  @spec get_user_primary_plan(User.t()) :: atom()
  def get_user_primary_plan(%User{} = user) do
    user.id
    |> OrganizationQueries.user_primary_plan()
    |> Repo.one()
    |> case do
      nil -> :free
      plan -> plan
    end
  end

  ## Invitations

  @doc """
  Invites a user (by email) to join the given organization with the given role.

  Generates a 32-byte cryptographically random token, stores its SHA-256 hash,
  and sends the raw token to the invitee by email. The raw token is returned
  to the caller for one-time display (e.g. testing); it is never persisted.
  """
  @spec invite_member(Organization.t(), User.t(), map()) ::
          {:ok, %{invitation: Invitation.t(), raw_token: String.t()}}
          | {:error, Ecto.Changeset.t()}
  def invite_member(%Organization{} = org, %User{} = inviter, attrs) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = :crypto.hash(:sha256, raw_token)

    invite_attrs = %{
      organization_id: org.id,
      email: attrs[:email] || attrs["email"],
      role: attrs[:role] || attrs["role"] || :member,
      token_hash: token_hash,
      invited_by_id: inviter.id,
      expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
    }

    case %Invitation{} |> Invitation.changeset(invite_attrs) |> Repo.insert() do
      {:ok, invitation} ->
        _ = OrgInvitationNotifier.deliver_invitation(invitation, raw_token)
        {:ok, %{invitation: invitation, raw_token: raw_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Accepts an invitation by raw token.

  - Verifies the token by SHA-256 hash lookup (constant-time DB compare).
  - Rejects expired or already-accepted tokens.
  - Creates a `User` if no account with that email exists yet, optionally
    setting the password from `attrs[:password]`.
  - Creates the organization membership.
  - Marks the invitation `accepted_at`.

  Idempotent: a second call with the same token returns
  `{:error, :invalid_token}` because `accepted_at` is no longer `nil`.
  """
  @spec accept_invitation(String.t(), map()) ::
          {:ok, %{user: User.t(), membership: Membership.t(), organization: Organization.t()}}
          | {:error, :invalid_token}
          | {:error, Ecto.Changeset.t()}
          | {:error, atom()}
  def accept_invitation(raw_token, attrs \\ %{}) when is_binary(raw_token) do
    token_hash = :crypto.hash(:sha256, raw_token)

    Repo.transaction(fn ->
      case fetch_pending_invitation(token_hash) do
        %Invitation{} = invitation ->
          accept_verified_invitation(invitation, token_hash, attrs)

        nil ->
          Repo.rollback(:invalid_token)
      end
    end)
  end

  defp accept_verified_invitation(invitation, token_hash, attrs) do
    if Plug.Crypto.secure_compare(invitation.token_hash, token_hash) do
      finalize_acceptance(invitation, attrs)
    else
      Repo.rollback(:invalid_token)
    end
  end

  @doc """
  Looks up a pending (unaccepted, unexpired) invitation by raw token.

  Returns the `Invitation` with its `:organization` preloaded, or `nil` if no
  matching pending invitation exists. Use this from read-only callers (e.g.
  the accept LiveView's `mount/3`); the write path inside `accept_invitation/2`
  uses a `FOR UPDATE`-locked private query of its own.
  """
  @spec find_pending_invitation(String.t()) :: Invitation.t() | nil
  def find_pending_invitation(raw_token) when is_binary(raw_token) do
    token_hash = :crypto.hash(:sha256, raw_token)
    now = DateTime.utc_now()

    Repo.one(
      from i in Invitation,
        where: i.token_hash == ^token_hash and is_nil(i.accepted_at) and i.expires_at > ^now,
        preload: [:organization]
    )
  end

  def find_pending_invitation(_), do: nil

  defp fetch_pending_invitation(token_hash) do
    now = DateTime.utc_now()

    query =
      from i in Invitation,
        where: i.token_hash == ^token_hash and is_nil(i.accepted_at) and i.expires_at > ^now,
        lock: "FOR UPDATE"

    Repo.one(query)
  end

  defp finalize_acceptance(%Invitation{} = invitation, attrs) do
    with {:ok, user} <- get_or_create_user(invitation.email, attrs),
         {:ok, membership} <-
           ensure_membership(invitation.organization_id, user, invitation.role),
         {:ok, _accepted} <- mark_accepted(invitation) do
      org = Repo.get!(Organization, invitation.organization_id)
      %{user: user, membership: membership, organization: org}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp get_or_create_user(email, attrs) do
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        with {:ok, user} <- Accounts.register_user(%{email: email}) do
          maybe_set_password(user, attrs[:password] || attrs["password"])
        end
    end
  end

  defp maybe_set_password(%User{} = user, nil) do
    # No password provided — confirm the account so it is usable via magic link.
    user |> User.confirm_changeset() |> Repo.update()
  end

  defp maybe_set_password(%User{} = user, password) when is_binary(password) do
    user
    |> User.password_changeset(%{password: password}, hash_password: true)
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
    |> Repo.update()
  end

  defp ensure_membership(org_id, %User{} = user, role) do
    case Repo.get_by(Membership, organization_id: org_id, user_id: user.id) do
      nil ->
        %Membership{}
        |> Membership.changeset(%{
          organization_id: org_id,
          user_id: user.id,
          role: role
        })
        |> Repo.insert()

      %Membership{} = membership ->
        {:ok, membership}
    end
  end

  defp mark_accepted(%Invitation{} = invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: DateTime.utc_now())
    |> Repo.update()
  end
end
