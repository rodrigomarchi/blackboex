defmodule Blackboex.Apis.Deployer do
  @moduledoc """
  Zero-downtime deployment of API versions.

  Compiles a new version, runs a smoke test, and promotes it if successful.
  Falls back to the previous version on failure.
  """

  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations.Organization

  require Logger

  @spec deploy(Api.t(), Organization.t()) ::
          {:ok, Api.t()} | {:error, :not_published | :compilation_failed | :smoke_test_failed}
  def deploy(%Api{status: "published"} = api, %Organization{} = org) do
    with {:ok, module} <- Compiler.compile(api, api.source_code),
         :ok <- smoke_test(module, api) do
      # Update registry with new module
      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth,
        visibility: api.visibility
      )

      Logger.info("Deployed API #{api.id} successfully")
      {:ok, api}
    else
      {:error, _} = error ->
        Logger.warning("Deploy failed for API #{api.id}: #{inspect(error)}")
        error
    end
  end

  def deploy(%Api{}, _org), do: {:error, :not_published}

  @spec rollback_deploy(Api.t(), integer(), integer() | nil) ::
          {:ok, Api.t()} | {:error, term()}
  def rollback_deploy(%Api{} = api, target_version, created_by_id \\ nil) do
    case Apis.rollback_to_version(api, target_version, created_by_id) do
      {:ok, version} ->
        case Compiler.compile(api, version.code) do
          {:ok, module} ->
            api_preloaded = Blackboex.Repo.preload(api, :organization)

            Registry.register(api.id, module,
              org_slug: api_preloaded.organization.slug,
              slug: api.slug,
              requires_auth: api.requires_auth,
              visibility: api.visibility
            )

            {:ok, api}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp smoke_test(module, api) do
    sample_input = api.example_request || %{}

    encoded =
      try do
        Jason.encode!(sample_input)
      rescue
        _ -> "{}"
      end

    try do
      unless function_exported?(module, :init, 1) and function_exported?(module, :call, 2) do
        raise "Module does not implement Plug behaviour"
      end

      conn =
        Plug.Test.conn(:post, "/", encoded)
        |> Plug.Conn.put_req_header("content-type", "application/json")

      plug_opts = module.init([])
      result_conn = module.call(conn, plug_opts)

      if result_conn.status in 200..299 do
        :ok
      else
        {:error, :smoke_test_failed}
      end
    rescue
      error ->
        Logger.warning("Smoke test failed: #{Exception.message(error)}")
        {:error, :smoke_test_failed}
    end
  end
end
