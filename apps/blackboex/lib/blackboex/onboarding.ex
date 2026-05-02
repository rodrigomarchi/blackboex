defmodule Blackboex.Onboarding do
  @moduledoc """
  First-run onboarding: atomically creates the platform admin user,
  organization, default project, membership, and instance settings.

  Race-safe via `LOCK TABLE instance_settings IN ACCESS EXCLUSIVE MODE`
  inside the wrapping transaction; concurrent callers serialize on the
  lock and the late winner sees `setup_completed?/0` true and gets
  `{:error, :already_completed}`.
  """

  alias Blackboex.Accounts.User
  alias Blackboex.Organizations
  alias Blackboex.Organizations.Organization
  alias Blackboex.Projects.Project
  alias Blackboex.Repo
  alias Blackboex.Settings

  @type complete_attrs :: %{
          required(:app_name) => String.t(),
          required(:public_url) => String.t(),
          required(:email) => String.t(),
          required(:password) => String.t(),
          required(:org_name) => String.t()
        }

  @type complete_result ::
          {:ok, %{user: User.t(), organization: Organization.t(), project: Project.t()}}
          | {:error, :already_completed}
          | {:error, Ecto.Changeset.t()}

  @doc """
  Completes the first-run setup. Idempotent on repeated calls — once
  `Blackboex.Settings.setup_completed?/0` is true, returns
  `{:error, :already_completed}`.
  """
  @spec complete_first_run(map()) :: complete_result()
  def complete_first_run(attrs) do
    with {:ok, attrs} <- normalize_keys(attrs),
         :ok <- validate_inputs(attrs) do
      run_in_transaction(attrs)
    end
  end

  defp run_in_transaction(attrs) do
    case Repo.transaction(fn -> run_setup(attrs) end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_setup(attrs) do
    Repo.query!("LOCK TABLE instance_settings IN ACCESS EXCLUSIVE MODE")
    Settings.invalidate_cache()

    if Settings.setup_completed?() do
      Repo.rollback(:already_completed)
    else
      do_setup(attrs)
    end
  end

  defp do_setup(attrs) do
    with {:ok, user} <- create_admin(attrs),
         {:ok, org} <- create_org(user, attrs.org_name),
         {:ok, project} <- fetch_sample_project(org, user),
         _settings <-
           Settings.mark_setup_completed!(%{
             app_name: attrs.app_name,
             public_url: attrs.public_url
           }) do
      %{user: user, organization: org, project: project}
    else
      {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp create_admin(%{email: email, password: password}) do
    %User{}
    |> User.email_changeset(%{email: email})
    |> User.password_changeset(%{password: password}, hash_password: true)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
    |> Ecto.Changeset.put_change(:is_platform_admin, true)
    |> Repo.insert()
  end

  defp create_org(user, org_name) do
    case Organizations.create_organization(user, %{name: org_name}) do
      {:ok, %{organization: org}} -> {:ok, org}
      {:error, _step, %Ecto.Changeset{} = cs, _changes} -> {:error, cs}
    end
  end

  defp fetch_sample_project(org, _user) do
    {:ok, Repo.get_by!(Project, organization_id: org.id, sample_workspace: true)}
  end

  defp validate_inputs(attrs) do
    types = %{
      app_name: :string,
      public_url: :string,
      email: :string,
      password: :string,
      org_name: :string
    }

    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(attrs, Map.keys(types))
      |> Ecto.Changeset.update_change(:app_name, &maybe_trim/1)
      |> Ecto.Changeset.update_change(:org_name, &maybe_trim/1)
      |> Ecto.Changeset.update_change(:email, &maybe_trim/1)
      |> Ecto.Changeset.update_change(:public_url, &maybe_trim/1)
      |> Ecto.Changeset.validate_required(Map.keys(types))
      |> Ecto.Changeset.validate_length(:password, min: 12, max: 72)
      |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> Ecto.Changeset.validate_format(:public_url, ~r{^https?://},
        message: "must be a valid http(s) URL"
      )

    if changeset.valid? do
      :ok
    else
      {:error, %{changeset | action: :validate}}
    end
  end

  defp maybe_trim(value) when is_binary(value), do: String.trim(value)
  defp maybe_trim(value), do: value

  defp normalize_keys(attrs) when is_map(attrs) do
    allowed = [:app_name, :public_url, :email, :password, :org_name]

    {:ok,
     attrs
     |> Enum.flat_map(fn
       {k, v} when is_binary(k) ->
         case Enum.find(allowed, &(Atom.to_string(&1) == k)) do
           nil -> []
           key -> [{key, v}]
         end

       {k, v} when is_atom(k) ->
         if k in allowed, do: [{k, v}], else: []
     end)
     |> Map.new()}
  end
end
