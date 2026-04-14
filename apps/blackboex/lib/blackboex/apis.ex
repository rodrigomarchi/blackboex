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

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiQueries
  alias Blackboex.Apis.Registry
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations
  alias Blackboex.Repo

  # ── API CRUD (direct in facade) ─────────────────────────────

  @spec create_api(map()) ::
          {:ok, Api.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_exceeded, map()}
  def create_api(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]

    if org_id do
      create_api_with_lock(attrs, org_id)
    else
      %Api{}
      |> Api.changeset(attrs)
      |> Repo.insert()
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

  @spec update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api(%Api{} = api, attrs) do
    api
    |> Api.update_changeset(attrs)
    |> Repo.update()
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
end
