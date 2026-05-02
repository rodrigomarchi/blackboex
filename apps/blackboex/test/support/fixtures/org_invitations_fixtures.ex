defmodule Blackboex.OrgInvitationsFixtures do
  @moduledoc "Fixtures for `Blackboex.Organizations` invitations."

  alias Blackboex.Organizations.Invitation
  alias Blackboex.Repo

  @doc """
  Creates a pending org invitation. Returns `%{invitation: Invitation.t(), raw_token: String.t()}`.

  Required attrs: `:organization_id`, `:invited_by_id`.
  Optional: `:email`, `:role`, `:expires_at`, `:raw_token`.
  """
  @spec org_invitation_fixture(map()) :: %{invitation: Invitation.t(), raw_token: String.t()}
  def org_invitation_fixture(attrs \\ %{}) do
    org_id = Map.fetch!(attrs, :organization_id)
    inviter_id = Map.fetch!(attrs, :invited_by_id)

    raw_token =
      Map.get(
        attrs,
        :raw_token,
        :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      )

    token_hash = :crypto.hash(:sha256, raw_token)

    {:ok, invitation} =
      %Invitation{}
      |> Invitation.changeset(%{
        organization_id: org_id,
        invited_by_id: inviter_id,
        email:
          Map.get(attrs, :email, "invitee-#{System.unique_integer([:positive])}@example.com"),
        role: Map.get(attrs, :role, :member),
        token_hash: token_hash,
        expires_at: Map.get(attrs, :expires_at, DateTime.add(DateTime.utc_now(), 7, :day))
      })
      |> Repo.insert()

    %{invitation: invitation, raw_token: raw_token}
  end

  @doc "Creates an already-expired org invitation."
  @spec expired_org_invitation_fixture(map()) :: %{
          invitation: Invitation.t(),
          raw_token: String.t()
        }
  def expired_org_invitation_fixture(attrs) do
    org_invitation_fixture(
      Map.put(attrs, :expires_at, DateTime.add(DateTime.utc_now(), -1, :day))
    )
  end
end
