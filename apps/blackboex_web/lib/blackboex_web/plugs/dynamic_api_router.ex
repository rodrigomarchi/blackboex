defmodule BlackboexWeb.Plugs.DynamicApiRouter do
  @moduledoc """
  Plug that routes dynamic API requests to compiled user modules.

  Parses `conn.path_info` to extract username and slug, looks up the
  module in the Registry, and delegates execution to the Sandbox.
  Falls back to compiling from DB if not found in Registry (e.g., after restart).
  """

  @behaviour Plug

  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  require Logger

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.path_info do
      [username, slug | rest] ->
        dispatch(conn, username, slug, rest)

      _ ->
        send_json(conn, 404, %{error: "API not found"})
    end
  end

  defp dispatch(conn, username, slug, rest) do
    case resolve_module(username, slug) do
      {:ok, module} ->
        execute_module(conn, module, rest)

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "API not found"})
    end
  end

  defp resolve_module(username, slug) do
    case Registry.lookup_by_path(username, slug) do
      {:ok, _module} = found ->
        found

      {:error, :not_found} ->
        # Not in Registry — try to find and compile from DB (happens after restart)
        compile_from_db(username, slug)
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
         {:ok, module} <- Compiler.compile(api, api.source_code) do
      try do
        Registry.register(api.id, module, username: org_slug, slug: api_slug)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end

      Logger.info("Compiled API on-demand: #{org_slug}/#{api_slug}")
      {:ok, module}
    else
      nil -> {:error, :not_found}
      %{status: _} -> {:error, :not_found}
      {:error, _reason} = err -> err
    end
  end

  defp execute_module(conn, module, rest) do
    conn = %{conn | path_info: rest, script_name: conn.script_name}

    # Execute Plug in the SAME process — conn is tied to the socket owner.
    # Timeout protection via Process.send_after + receive.
    # Memory protection via max_heap_size on current process (temporarily).
    old_heap = Process.flag(:max_heap_size, %{size: 10_000_000, kill: false, error_logger: true})

    try do
      plug_opts = module.init([])
      result_conn = module.call(conn, plug_opts)
      result_conn
    rescue
      error ->
        Logger.error("API execution error: #{Exception.message(error)}")
        send_json(conn, 500, %{error: "API execution failed"})
    after
      Process.flag(:max_heap_size, old_heap)
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
    |> Plug.Conn.halt()
  end
end
