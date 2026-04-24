defmodule BlackboexWeb.Plugs.DynamicApiRouter do
  @moduledoc """
  Plug that routes dynamic API requests to compiled user modules.

  Pipeline: resolve → rate_limit → auth → execute → log

  Rate limiting and auth only apply to published APIs.
  Compiled (non-published) APIs are served for internal testing only.
  """

  @behaviour Plug

  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.Registry
  alias Blackboex.Billing
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Sandbox
  alias Blackboex.ProjectEnvVars
  alias Blackboex.Telemetry.Events
  alias BlackboexWeb.Plugs.ApiAuth
  alias BlackboexWeb.Plugs.ApiDocsPlug
  alias BlackboexWeb.Plugs.RateLimiter

  @doc_paths ~w(docs openapi.json openapi.yaml)

  require Logger

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.path_info do
      [org_slug, project_slug, slug | rest]
      when project_slug not in @doc_paths ->
        dispatch(conn, org_slug, project_slug, slug, rest)

      [org_slug, slug | rest] ->
        dispatch_legacy(conn, org_slug, slug, rest)

      _ ->
        send_json(conn, 404, %{error: "API not found"})
    end
  end

  # 3-part path: /api/:org_slug/:project_slug/:api_slug/*rest
  # Falls back to legacy 2-part dispatch when the triple-key lookup fails,
  # preserving backward compat for /api/:org/:api/:sub-path URLs.
  defp dispatch(conn, org_slug, project_slug, slug, rest) do
    case {resolve_api(org_slug, project_slug, slug), rest} do
      {{:ok, _mod, _meta, api}, [doc_path]}
      when doc_path in @doc_paths ->
        serve_docs(conn, api, org_slug, slug, doc_path)

      {{:ok, module, metadata, api}, _rest} ->
        run_pipeline(conn, module, metadata, api, rest)

      {{:error, :shutting_down}, _} ->
        send_json(conn, 503, %{error: "Service is shutting down"})

      {{:error, :not_found}, _} ->
        # project_slug may actually be the api_slug in the legacy 2-part format
        dispatch_legacy(conn, org_slug, project_slug, [slug | rest])
    end
  end

  # Legacy 2-part path: /api/:org_slug/:api_slug/*rest (backward compat)
  defp dispatch_legacy(conn, org_slug, slug, rest) do
    case {resolve_api(org_slug, slug), rest} do
      {{:ok, _mod, _meta, api}, [doc_path]}
      when doc_path in @doc_paths ->
        serve_docs(conn, api, org_slug, slug, doc_path)

      {{:ok, module, metadata, api}, _rest} ->
        run_pipeline(conn, module, metadata, api, rest)

      {{:error, :shutting_down}, _} ->
        send_json(conn, 503, %{error: "Service is shutting down"})

      {{:error, :not_found}, _} ->
        send_json(conn, 404, %{error: "API not found"})
    end
  end

  defp serve_docs(conn, api, org_slug, slug, "docs") do
    ApiDocsPlug.serve_swagger_ui(conn, api, org_slug, slug)
  end

  defp serve_docs(conn, api, org_slug, slug, "openapi.json") do
    ApiDocsPlug.serve_spec_json(conn, api, org_slug, slug)
  end

  defp serve_docs(conn, api, org_slug, slug, "openapi.yaml") do
    ApiDocsPlug.serve_spec_yaml(conn, api, org_slug, slug)
  end

  defp run_pipeline(conn, module, metadata, api, rest) do
    start_time = System.monotonic_time(:millisecond)

    result =
      with {:ok, conn} <- maybe_rate_limit(conn, api, metadata),
           {:ok, conn} <- maybe_authenticate(conn, api, metadata),
           {:ok, conn} <- maybe_check_enforcement(conn, api) do
        conn = assign_project_env(conn, api)
        {resp_conn, error_msg} = execute_module(conn, module, rest)
        {:ok, resp_conn, error_msg}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, result_conn, error_msg} ->
        log_request(conn, result_conn, metadata, api, duration_ms, error_msg)
        result_conn

      {:error, :rate_limited, retry_after} ->
        resp_conn =
          conn
          |> Plug.Conn.put_resp_header("retry-after", to_string(retry_after))
          |> send_json(429, %{error: "Rate limit exceeded", retry_after: retry_after})

        log_request(conn, resp_conn, metadata, api, duration_ms)
        resp_conn

      {:error, :limit_exceeded, details} ->
        resp_conn =
          send_json(conn, 402, %{
            error: "Plan limit exceeded",
            limit: details.limit,
            current: details.current,
            plan: details.plan,
            upgrade_url: "/billing"
          })

        log_request(conn, resp_conn, metadata, api, duration_ms)
        resp_conn

      {:error, auth_reason} ->
        resp_conn = send_auth_error(conn, auth_reason)
        log_request(conn, resp_conn, metadata, api, duration_ms)
        resp_conn
    end
  end

  defp maybe_rate_limit(conn, api, metadata) do
    if api.status == "published" do
      RateLimiter.check_rate(conn, metadata)
    else
      RateLimiter.check_rate_draft(conn)
    end
  end

  defp maybe_authenticate(conn, api, metadata) do
    if api.status == "published" do
      ApiAuth.authenticate(conn, api, metadata)
    else
      {:ok, conn}
    end
  end

  defp maybe_check_enforcement(conn, %{status: "published"} = api) do
    case Blackboex.Organizations.get_organization(api.organization_id) do
      nil -> {:ok, conn}
      org -> check_invocation_limit(conn, org)
    end
  end

  defp maybe_check_enforcement(conn, _api), do: {:ok, conn}

  defp check_invocation_limit(conn, org) do
    case Enforcement.check_limit(org, :api_invocation) do
      {:ok, _remaining} -> {:ok, conn}
      {:error, :limit_exceeded, details} -> {:error, :limit_exceeded, details}
    end
  end

  defp send_auth_error(conn, :missing_key) do
    send_json(conn, 401, %{
      error: "API key required",
      hint: "Pass via Authorization: Bearer bb_live_... header"
    })
  end

  defp send_auth_error(conn, :invalid) do
    send_json(conn, 401, %{error: "Invalid API key"})
  end

  defp send_auth_error(conn, :revoked) do
    send_json(conn, 401, %{error: "API key has been revoked"})
  end

  defp send_auth_error(conn, :expired) do
    send_json(conn, 401, %{error: "API key has expired"})
  end

  defp resolve_api(org_slug, project_slug, api_slug) do
    case Registry.lookup_by_path(org_slug, project_slug, api_slug) do
      {:ok, module, metadata} ->
        api = load_api_struct(metadata.api_id)

        if api do
          {:ok, module, metadata, api}
        else
          {:error, :not_found}
        end

      {:error, :shutting_down} ->
        {:error, :shutting_down}

      {:error, :not_found} ->
        compile_from_db(org_slug, project_slug, api_slug)
    end
  end

  defp resolve_api(org_slug, slug) do
    case Registry.lookup_by_path(org_slug, slug) do
      {:ok, module, metadata} ->
        api = load_api_struct(metadata.api_id)

        if api do
          {:ok, module, metadata, api}
        else
          {:error, :not_found}
        end

      {:error, :shutting_down} ->
        {:error, :shutting_down}

      {:error, :not_found} ->
        compile_from_db(org_slug, slug)
    end
  end

  defp load_api_struct(api_id) do
    Blackboex.Repo.get(Blackboex.Apis.Api, api_id)
  end

  defp compile_from_db(org_slug, project_slug, api_slug) do
    import Ecto.Query, warn: false

    alias Blackboex.Apis.Api
    alias Blackboex.Organizations.Organization
    alias Blackboex.Projects.Project
    alias Blackboex.Repo

    with %Organization{id: org_id} <- Repo.get_by(Organization, slug: org_slug),
         %Project{id: project_id} <-
           Repo.get_by(Project, slug: project_slug, organization_id: org_id),
         %Api{status: status} = api
         when status in ["compiled", "published"] <-
           Repo.get_by(Api, slug: api_slug, project_id: project_id),
         source_files = Blackboex.Apis.list_source_files(api.id),
         {:ok, module} <- Compiler.compile_files(api, source_files) do
      metadata = %{
        requires_auth: api.requires_auth,
        visibility: api.visibility,
        api_id: api.id
      }

      try do
        Registry.register(api.id, module,
          org_slug: org_slug,
          project_slug: project_slug,
          slug: api_slug,
          requires_auth: api.requires_auth,
          visibility: api.visibility
        )
      rescue
        error ->
          Logger.warning(
            "Registry.register failed for #{org_slug}/#{project_slug}/#{api_slug}: #{Exception.message(error)}"
          )

          :ok
      catch
        :exit, reason ->
          Logger.warning(
            "Registry.register exited for #{org_slug}/#{project_slug}/#{api_slug}: #{inspect(reason)}"
          )

          :ok
      end

      Logger.info("Compiled API on-demand: #{org_slug}/#{project_slug}/#{api_slug}")
      {:ok, module, metadata, api}
    else
      nil -> {:error, :not_found}
      %{status: _} -> {:error, :not_found}
      {:error, _reason} = err -> err
    end
  end

  defp compile_from_db(org_slug, api_slug) do
    import Ecto.Query, warn: false

    alias Blackboex.Apis.Api
    alias Blackboex.Organizations.Organization
    alias Blackboex.Repo

    with %Organization{id: org_id} <- Repo.get_by(Organization, slug: org_slug),
         %Api{status: status} = api when status in ["compiled", "published"] <-
           Repo.get_by(Api, slug: api_slug, organization_id: org_id),
         source_files = Blackboex.Apis.list_source_files(api.id),
         {:ok, module} <- Compiler.compile_files(api, source_files) do
      metadata = %{
        requires_auth: api.requires_auth,
        visibility: api.visibility,
        api_id: api.id
      }

      try do
        Registry.register(api.id, module,
          org_slug: org_slug,
          slug: api_slug,
          requires_auth: api.requires_auth,
          visibility: api.visibility
        )
      rescue
        error ->
          Logger.warning(
            "Registry.register failed for #{org_slug}/#{api_slug}: #{Exception.message(error)}"
          )

          :ok
      catch
        :exit, reason ->
          Logger.warning(
            "Registry.register exited for #{org_slug}/#{api_slug}: #{inspect(reason)}"
          )

          :ok
      end

      Logger.info("Compiled API on-demand: #{org_slug}/#{api_slug}")
      {:ok, module, metadata, api}
    else
      nil -> {:error, :not_found}
      %{status: _} -> {:error, :not_found}
      {:error, _reason} = err -> err
    end
  end

  # Loads the project's env vars and assigns them to `conn.assigns.env` so
  # compiled Handler code can read `conn.assigns.env["KEY"]`. Defensive against
  # missing `project_id` (legacy APIs) — falls back to an empty map.
  @spec assign_project_env(Plug.Conn.t(), Blackboex.Apis.Api.t()) :: Plug.Conn.t()
  defp assign_project_env(conn, %{project_id: nil}), do: Plug.Conn.assign(conn, :env, %{})

  defp assign_project_env(conn, %{project_id: project_id}) do
    Plug.Conn.assign(conn, :env, ProjectEnvVars.load_runtime_map(project_id))
  end

  defp execute_module(conn, module, rest) do
    conn = %{conn | path_info: rest, script_name: conn.script_name}

    case Sandbox.execute_plug(module, conn, timeout: 30_000) do
      {:ok, result_conn} ->
        {result_conn, extract_error_from_response(result_conn)}

      {:error, :timeout} ->
        error = "API execution timed out"
        Logger.warning("API execution timeout: #{inspect(module)}")
        {send_json(conn, 504, %{error: error}), error}

      {:error, :memory_exceeded} ->
        error = "API execution exceeded memory limit"
        Logger.warning("API execution memory exceeded: #{inspect(module)}")
        {send_json(conn, 503, %{error: error}), error}

      {:error, {:exception, message}} ->
        env = conn.assigns[:env] || %{}
        redacted_msg = redact_env_values(message, env)
        sanitized = sanitize_error(redacted_msg)
        Logger.error("API execution error: #{redacted_msg}")
        {send_json(conn, 500, %{error: "API execution failed", detail: sanitized}), sanitized}

      {:error, {:runtime, reason}} ->
        env = conn.assigns[:env] || %{}
        redacted_reason = redact_env_values(inspect(reason), env)
        sanitized = sanitize_error(redacted_reason)
        Logger.error("API runtime error: #{inspect(module)} — #{redacted_reason}")
        {send_json(conn, 500, %{error: "API execution failed", detail: sanitized}), sanitized}
    end
  end

  defp log_request(conn, result_conn, metadata, api, duration_ms, error_message \\ nil) do
    Events.emit_api_request(%{
      duration_ms: duration_ms,
      api_id: metadata.api_id,
      method: conn.method,
      status_code: result_conn.status
    })

    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    Analytics.log_invocation(%{
      api_id: metadata.api_id,
      project_id: api.project_id,
      api_key_id:
        case result_conn.assigns do
          %{api_key: %{id: id}} -> id
          _ -> nil
        end,
      method: conn.method,
      path: "/" <> Enum.join(conn.path_info, "/"),
      status_code: result_conn.status,
      duration_ms: duration_ms,
      request_body_size: raw_body_size(conn.assigns[:raw_body]),
      response_body_size: byte_size(result_conn.resp_body || ""),
      ip_address: ip,
      error_message: error_message
    })

    if api.status == "published" do
      Billing.record_usage_event(%{
        organization_id: api.organization_id,
        project_id: api.project_id,
        event_type: "api_invocation",
        metadata: %{api_id: api.id}
      })
    end
  end

  defp raw_body_size(nil), do: 0
  defp raw_body_size(body) when is_binary(body), do: byte_size(body)
  defp raw_body_size(body) when is_list(body), do: body |> IO.iodata_length()

  defp extract_error_from_response(%{assigns: %{handler_error: detail}}) when is_binary(detail),
    do: detail

  defp extract_error_from_response(%{status: status, resp_body: body})
       when status >= 400 and is_binary(body) and byte_size(body) > 0 do
    case Jason.decode(body) do
      {:ok, %{"detail" => detail}} when is_binary(detail) -> detail
      _ -> nil
    end
  end

  defp extract_error_from_response(_), do: nil

  defp sanitize_error(message) when is_binary(message) do
    # Remove module paths (Elixir.Blackboex.DynamicApi.Api_xxx...) for cleaner output
    message
    |> String.replace(~r/Blackboex\.DynamicApi\.Api_[a-f0-9_]+\./, "")
    |> String.replace(~r/Elixir\./, "")
    |> String.slice(0, 500)
  end

  # Redacts env values from error messages BEFORE logging / responding, so
  # secrets like API keys can never leak via a 500 response or log line.
  # Only values with `byte_size >= 8` are replaced — short env values
  # (`"1"`, `"true"`, `"GET"`) would corrupt unrelated output text.
  @env_redact_min_length 8

  @spec redact_env_values(String.t(), map()) :: String.t()
  defp redact_env_values(message, env) when is_binary(message) and is_map(env) do
    Enum.reduce(env, message, fn {name, value}, acc ->
      if is_binary(value) and byte_size(value) >= @env_redact_min_length do
        String.replace(acc, value, "{{env.#{name}}}")
      else
        acc
      end
    end)
  end

  defp redact_env_values(message, _env) when is_binary(message), do: message

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
    |> Plug.Conn.halt()
  end
end
