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
          required(:org_name) => String.t(),
          required(:project_name) => String.t()
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
         {:ok, project} <- create_project(org, user, attrs.project_name),
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

  defp create_project(org, _user, project_name) do
    # `Organizations.create_organization/2` already created a "Default" project
    # and a project membership for the user; rename it if the operator chose
    # a different name. Keeping the same membership avoids unique constraint
    # collisions and keeps the API context-shaped to a single project.
    project =
      Repo.get_by!(Project, organization_id: org.id)

    if is_binary(project_name) and String.trim(project_name) != "" and
         project.name != project_name do
      project
      |> Project.changeset(%{name: project_name})
      |> Repo.update()
    else
      {:ok, project}
    end
  end

  defp validate_inputs(attrs) do
    types = %{
      app_name: :string,
      public_url: :string,
      email: :string,
      password: :string,
      org_name: :string,
      project_name: :string
    }

    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(attrs, Map.keys(types))
      |> Ecto.Changeset.update_change(:app_name, &maybe_trim/1)
      |> Ecto.Changeset.update_change(:org_name, &maybe_trim/1)
      |> Ecto.Changeset.update_change(:project_name, &maybe_trim/1)
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
    {:ok,
     Enum.into(attrs, %{}, fn
       {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
       {k, v} when is_atom(k) -> {k, v}
     end)}
  rescue
    ArgumentError -> {:error, :invalid_attrs}
  end
end
