defmodule Blackboex.Apis do
  @moduledoc """
  The Apis context. Manages API endpoints created by users.

  Each API has a virtual filesystem of ApiFiles with revision history.
  ApiVersions represent compiled snapshots referencing specific file revisions.

  This facade delegates to focused sub-contexts:
  - `Apis.Files` — file CRUD and revision tracking
  - `Apis.Versions` — version snapshots, diffs, rollbacks
  - `Apis.Lifecycle` — publishing and unpublishing
  - `Apis.Templates` — API creation from templates and generation results
  - `Apis.Keys` — API key management
  - `Apis.Analytics` — invocation logging and metrics
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiQueries
  alias Blackboex.Apis.Registry
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations
  alias Blackboex.Projects
  alias Blackboex.Repo

  # ── API CRUD (direct in facade) ─────────────────────────────

  @spec create_api(map()) ::
          {:ok, Api.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
          | {:error, :limit_exceeded, map()}
  def create_api(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]
    project_id = attrs[:project_id] || attrs["project_id"]

    with :ok <- ensure_project_in_org(project_id, org_id) do
      if org_id do
        create_api_with_lock(attrs, org_id)
      else
        %Api{}
        |> Api.changeset(attrs)
        |> Repo.insert()
      end
    end
  end

  @spec list_apis(Ecto.UUID.t()) :: [Api.t()]
  def list_apis(organization_id) do
    organization_id |> ApiQueries.list_for_org() |> Repo.all()
  end

  @spec list_apis_for_project(Ecto.UUID.t()) :: [Api.t()]
  def list_apis_for_project(project_id) do
    project_id |> ApiQueries.list_for_project() |> Repo.all()
  end

  @spec list_for_project(Ecto.UUID.t(), keyword()) :: [Api.t()]
  def list_for_project(project_id, opts \\ []) do
    project_id |> ApiQueries.list_for_project_sorted(opts) |> Repo.all()
  end

  @spec count_apis_for_org(Ecto.UUID.t()) :: non_neg_integer()
  def count_apis_for_org(organization_id) do
    organization_id |> ApiQueries.list_for_org() |> Repo.aggregate(:count)
  end

  @spec count_apis_for_project(Ecto.UUID.t()) :: non_neg_integer()
  def count_apis_for_project(project_id) do
    project_id |> ApiQueries.list_for_project() |> Repo.aggregate(:count)
  end

  @spec get_api(Ecto.UUID.t(), Ecto.UUID.t()) :: Api.t() | nil
  def get_api(organization_id, api_id) do
    organization_id |> ApiQueries.by_org_and_id(api_id) |> Repo.one()
  end

  @spec get_api_by_slug(Ecto.UUID.t(), String.t()) :: Api.t() | nil
  def get_api_by_slug(project_id, slug) do
    project_id |> ApiQueries.by_project_and_slug(slug) |> Repo.one()
  end

  @doc """
  Fetches an API by organization_id and api_id. Returns `nil` when not found or
  the API does not belong to the given organization.
  """
  @spec get_for_org(Ecto.UUID.t(), Ecto.UUID.t()) :: Api.t() | nil
  def get_for_org(org_id, api_id) do
    org_id |> ApiQueries.by_org_and_id_only(api_id) |> Repo.one()
  end

  @spec update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api(%Api{} = api, attrs) do
    api
    |> Api.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves an API to a different project within the same organization.

  Validates that `new_project_id` belongs to the same org as the API.
  """
  @spec move_api(Api.t(), Ecto.UUID.t()) ::
          {:ok, Api.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def move_api(%Api{} = api, new_project_id) do
    with :ok <- ensure_project_in_org(new_project_id, api.organization_id) do
      api
      |> Api.move_project_changeset(%{project_id: new_project_id})
      |> Repo.update()
    end
  end

  @spec delete_api(Api.t()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def delete_api(%Api{} = api) do
    if api.status == "published" do
      Registry.unregister(api.id)

      module_name = Compiler.module_name_for(api)
      Compiler.unload(module_name)
    end

    Repo.delete(api)
  end

  # ── Files ───────────────────────────────────────────────────

  defdelegate list_files(api_id), to: Blackboex.Apis.Files
  defdelegate list_files_with_virtual(api), to: Blackboex.Apis.Files
  defdelegate list_source_files(api_id), to: Blackboex.Apis.Files
  defdelegate list_test_files(api_id), to: Blackboex.Apis.Files
  defdelegate get_file(api_id, path), to: Blackboex.Apis.Files
  defdelegate get_file!(file_id), to: Blackboex.Apis.Files
  defdelegate create_file(api, attrs), to: Blackboex.Apis.Files
  defdelegate update_file_content(file, new_content, opts \\ %{}), to: Blackboex.Apis.Files
  defdelegate delete_file(file), to: Blackboex.Apis.Files
  defdelegate list_file_revisions(file_id), to: Blackboex.Apis.Files
  defdelegate upsert_files(api, file_maps, opts \\ %{}), to: Blackboex.Apis.Files
  defdelegate build_file_snapshots(api_id), to: Blackboex.Apis.Files
  defdelegate get_source_for_compilation(api_id), to: Blackboex.Apis.Files
  defdelegate get_tests_for_running(api_id), to: Blackboex.Apis.Files

  # ── Versions ────────────────────────────────────────────────

  defdelegate create_version(api, attrs), to: Blackboex.Apis.Versions
  defdelegate list_versions(api_id), to: Blackboex.Apis.Versions
  defdelegate get_version(api_id, version_number), to: Blackboex.Apis.Versions
  defdelegate published_version(api_id), to: Blackboex.Apis.Versions
  defdelegate get_latest_version(api), to: Blackboex.Apis.Versions

  defdelegate rollback_to_version(api, target_version_number, created_by_id \\ nil),
    to: Blackboex.Apis.Versions

  # ── Lifecycle ───────────────────────────────────────────────

  defdelegate publish(api, org), to: Blackboex.Apis.Lifecycle
  defdelegate unpublish(api), to: Blackboex.Apis.Lifecycle

  # ── Templates ───────────────────────────────────────────────

  defdelegate create_api_with_files(attrs), to: Blackboex.Apis.Templates
  defdelegate create_api_from_template(attrs, template_id), to: Blackboex.Apis.Templates

  defdelegate create_api_from_generation(result, organization_id, user_id, name, project_id),
    to: Blackboex.Apis.Templates

  # ── Private ─────────────────────────────────────────────────

  defp create_api_with_lock(attrs, org_id) do
    Repo.transaction(fn ->
      acquire_api_creation_lock(org_id)
      check_and_insert_api(attrs, org_id)
    end)
    |> case do
      {:ok, api} -> {:ok, api}
      {:error, {:limit_exceeded, details}} -> {:error, :limit_exceeded, details}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  rescue
    e in Ecto.InvalidChangesetError -> {:error, e.changeset}
  end

  defp acquire_api_creation_lock(org_id) do
    lock_key = :erlang.phash2({"create_api", org_id})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
  end

  defp check_and_insert_api(attrs, org_id) do
    case Organizations.get_organization(org_id) do
      nil ->
        insert_api!(attrs)

      org ->
        case Enforcement.check_limit(org, :create_api) do
          {:ok, _remaining} -> insert_api!(attrs)
          {:error, :limit_exceeded, details} -> Repo.rollback({:limit_exceeded, details})
        end
    end
  end

  defp insert_api!(attrs) do
    %Api{}
    |> Api.changeset(attrs)
    |> Repo.insert!()
  end

  # Returns :ok when project_id is nil (project is optional) or when the
  # project exists and belongs to the given org. Returns {:error, :forbidden}
  # when a project_id is provided but does not belong to the org.
  defp ensure_project_in_org(nil, _org_id), do: :ok

  defp ensure_project_in_org(_project_id, nil), do: :ok

  defp ensure_project_in_org(project_id, org_id) do
    case Projects.get_project(org_id, project_id) do
      nil -> {:error, :forbidden}
      _project -> :ok
    end
  end
end
