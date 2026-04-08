defmodule Blackboex.Apis.Lifecycle do
  @moduledoc """
  Sub-context for API lifecycle transitions: publishing and unpublishing.
  """

  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.Registry
  alias Blackboex.Apis.VersionQueries
  alias Blackboex.Apis.Versions
  alias Blackboex.Audit
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo

  require Logger

  # ── Public API ──────────────────────────────────────────────

  @spec publish(Api.t(), Organization.t()) ::
          {:ok, Api.t()}
          | {:error, :not_compiled | :org_mismatch | Ecto.Changeset.t()}
  def publish(
        %Api{status: "compiled", organization_id: org_id} = api,
        %Organization{id: org_id} = org
      ) do
    case Apis.update_api(api, %{status: "published"}) do
      {:ok, published_api} ->
        register_published_api(published_api, org)

        version_label = generate_version_label(published_api.id)

        Versions.create_version(published_api, %{
          source: "publish",
          version_label: version_label
        })

        Audit.log_async("api.published", %{
          resource_type: "api",
          resource_id: published_api.id,
          user_id: published_api.user_id,
          organization_id: org.id
        })

        {:ok, published_api}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def publish(%Api{status: "compiled"}, %Organization{}), do: {:error, :org_mismatch}
  def publish(%Api{}, _org), do: {:error, :not_compiled}

  @spec unpublish(Api.t()) :: {:ok, Api.t()} | {:error, :not_published | Ecto.Changeset.t()}
  def unpublish(%Api{status: "published"} = api) do
    case Apis.update_api(api, %{status: "compiled"}) do
      {:ok, updated_api} ->
        Registry.unregister(api.id)

        module_name = Compiler.module_name_for(api)
        Compiler.unload(module_name)

        Audit.log_async("api.unpublished", %{
          resource_type: "api",
          resource_id: api.id,
          user_id: api.user_id,
          organization_id: api.organization_id
        })

        {:ok, updated_api}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def unpublish(%Api{}), do: {:error, :not_published}

  # ── Private ─────────────────────────────────────────────────

  defp generate_version_label(api_id) do
    today = Date.to_iso8601(Date.utc_today())
    count = count_versions_today(api_id)
    "prod-#{today}.#{String.pad_leading(to_string(count + 1), 2, "0")}"
  end

  defp count_versions_today(api_id) do
    today = Date.utc_today()

    api_id
    |> VersionQueries.count_labeled_today(today)
    |> Repo.aggregate(:count)
  end

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
