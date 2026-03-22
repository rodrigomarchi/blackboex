defmodule Blackboex.Apis do
  @moduledoc """
  The Apis context. Manages API endpoints created by users.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiVersion
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Apis.Keys
  alias Blackboex.Apis.Registry
  alias Blackboex.Audit
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.GenerationResult
  alias Blackboex.Organizations
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo

  require Logger

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

  @spec list_apis(Ecto.UUID.t()) :: [Api.t()]
  def list_apis(organization_id) do
    Api
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @spec get_api(Ecto.UUID.t(), Ecto.UUID.t()) :: Api.t() | nil
  def get_api(organization_id, api_id) do
    Api
    |> where([a], a.organization_id == ^organization_id and a.id == ^api_id)
    |> Repo.one()
  end

  @spec update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api(%Api{} = api, attrs) do
    api
    |> Api.changeset(attrs)
    |> Repo.update()
  end

  # --- Versioning ---

  @spec create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_version(%Api{} = api, attrs) do
    code = attrs[:code] || attrs["code"] || ""
    test_code = attrs[:test_code] || attrs["test_code"]

    Ecto.Multi.new()
    |> Ecto.Multi.run(:next_number, &next_version_number(&1, &2, api.id))
    |> Ecto.Multi.run(:diff_summary, &compute_diff_summary(&1, &2, api.id, code))
    |> Ecto.Multi.insert(:version, fn %{next_number: number, diff_summary: summary} ->
      ApiVersion.changeset(
        %ApiVersion{},
        Map.merge(attrs, %{api_id: api.id, version_number: number, diff_summary: summary})
      )
    end)
    |> Ecto.Multi.update(:api, Api.changeset(api, %{source_code: code, test_code: test_code}))
    |> Repo.transaction()
    |> unwrap_version_transaction()
  end

  defp next_version_number(repo, _changes, api_id) do
    result =
      ApiVersion
      |> where([v], v.api_id == ^api_id)
      |> select([v], max(v.version_number))
      |> repo.one()

    {:ok, (result || 0) + 1}
  end

  defp compute_diff_summary(repo, _changes, api_id, code) do
    latest =
      ApiVersion
      |> where([v], v.api_id == ^api_id)
      |> order_by([v], desc: v.version_number)
      |> limit(1)
      |> repo.one()

    summary = compute_diff_for_latest(latest, code)
    {:ok, summary}
  end

  defp compute_diff_for_latest(nil, _code), do: nil

  defp compute_diff_for_latest(latest, code) do
    diff = DiffEngine.compute_diff(latest.code, code)
    DiffEngine.format_diff_summary(diff)
  end

  defp unwrap_version_transaction({:ok, %{version: version}}), do: {:ok, version}
  defp unwrap_version_transaction({:error, :version, changeset, _}), do: {:error, changeset}
  defp unwrap_version_transaction({:error, :api, changeset, _}), do: {:error, changeset}
  defp unwrap_version_transaction({:error, _step, reason, _}), do: {:error, reason}

  @spec list_versions(Ecto.UUID.t()) :: [ApiVersion.t()]
  def list_versions(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
    |> Repo.all()
  end

  @spec get_version(Ecto.UUID.t(), integer()) :: ApiVersion.t() | nil
  def get_version(api_id, version_number) do
    ApiVersion
    |> where([v], v.api_id == ^api_id and v.version_number == ^version_number)
    |> Repo.one()
  end

  @spec get_latest_version(Api.t()) :: ApiVersion.t() | nil
  def get_latest_version(%Api{id: api_id}) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
    |> limit(1)
    |> Repo.one()
  end

  @spec rollback_to_version(Api.t(), integer(), integer() | nil) ::
          {:ok, ApiVersion.t()} | {:error, :version_not_found | Ecto.Changeset.t()}
  def rollback_to_version(%Api{} = api, target_version_number, created_by_id \\ nil) do
    case get_version(api.id, target_version_number) do
      nil ->
        {:error, :version_not_found}

      target ->
        create_version(api, %{
          code: target.code,
          test_code: target.test_code,
          source: "rollback",
          prompt: "Rollback to version #{target_version_number}",
          created_by_id: created_by_id
        })
    end
  end

  # --- API from generation ---

  @spec create_api_from_generation(GenerationResult.t(), Ecto.UUID.t(), integer(), String.t()) ::
          {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def create_api_from_generation(%GenerationResult{} = result, organization_id, user_id, name) do
    create_api(%{
      name: name,
      description: result.description,
      source_code: result.code,
      template_type: to_string(result.template),
      method: result.method || "POST",
      organization_id: organization_id,
      user_id: user_id,
      example_request: result.example_request,
      example_response: result.example_response,
      param_schema: result.param_schema
    })
  end

  # --- Publishing ---

  @spec publish(Api.t(), Organization.t()) ::
          {:ok, Api.t(), String.t()}
          | {:error, :not_compiled | :org_mismatch | Ecto.Changeset.t()}
  def publish(
        %Api{status: "compiled", organization_id: org_id} = api,
        %Organization{id: org_id} = org
      ) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:api, Api.changeset(api, %{status: "published"}))
    |> Ecto.Multi.run(:key, fn _repo, %{api: published_api} ->
      case Keys.create_key(published_api, %{
             label: "Default key",
             organization_id: org.id
           }) do
        {:ok, plain_key, api_key} -> {:ok, {plain_key, api_key}}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{api: published_api, key: {plain_key, _api_key}}} ->
        register_published_api(published_api, org)

        Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
          Audit.log("api.published", %{
            resource_type: "api",
            resource_id: published_api.id,
            user_id: published_api.user_id,
            organization_id: org.id
          })
        end)

        {:ok, published_api, plain_key}

      {:error, :api, changeset, _} ->
        {:error, changeset}

      {:error, :key, changeset, _} ->
        {:error, changeset}
    end
  end

  def publish(%Api{status: "compiled"}, %Organization{}), do: {:error, :org_mismatch}
  def publish(%Api{}, _org), do: {:error, :not_compiled}

  @spec unpublish(Api.t()) :: {:ok, Api.t()} | {:error, :not_published | Ecto.Changeset.t()}
  def unpublish(%Api{status: "published"} = api) do
    case update_api(api, %{status: "compiled"}) do
      {:ok, updated_api} ->
        Registry.unregister(api.id)

        module_name = Compiler.module_name_for(api)
        Compiler.unload(module_name)

        Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
          Audit.log("api.unpublished", %{
            resource_type: "api",
            resource_id: api.id,
            user_id: api.user_id,
            organization_id: api.organization_id
          })
        end)

        {:ok, updated_api}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def unpublish(%Api{}), do: {:error, :not_published}

  defp register_published_api(api, org) do
    Registry.register(api.id, Compiler.module_name_for(api),
      org_slug: org.slug,
      slug: api.slug,
      requires_auth: api.requires_auth,
      visibility: api.visibility
    )
  rescue
    error ->
      Logger.warning("Failed to register published API #{api.id}: #{inspect(error)}")
  end
end
