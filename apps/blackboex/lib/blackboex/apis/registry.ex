defmodule Blackboex.Apis.Registry do
  @moduledoc """
  ETS-based registry for compiled API modules.

  Provides O(1) lookup by api_id or by {org_slug, api_slug} path.
  Stores module and metadata (requires_auth, visibility) for each API.
  Reloads compiled/published APIs from the database on init.
  """

  use GenServer

  require Logger

  @table :api_registry
  @path_table :api_registry_paths
  @shutdown_flag :api_registry_shutting_down
  @drain_timeout_ms 30_000
  @drain_poll_ms 500

  @type metadata :: %{
          requires_auth: boolean(),
          visibility: String.t(),
          api_id: Ecto.UUID.t()
        }

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register(Ecto.UUID.t(), module(), keyword()) :: :ok
  def register(api_id, module, opts \\ []) do
    GenServer.call(__MODULE__, {:register, api_id, module, opts})
  end

  @spec lookup(Ecto.UUID.t()) ::
          {:ok, module(), metadata()} | {:error, :not_found | :shutting_down}
  def lookup(api_id) do
    if shutting_down?(), do: throw(:shutting_down)

    case :ets.lookup(@table, api_id) do
      [{^api_id, {module, metadata}}] -> {:ok, module, metadata}
      # Legacy format compatibility (module without metadata)
      [{^api_id, module}] when is_atom(module) -> {:ok, module, default_metadata(api_id)}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  catch
    :shutting_down -> {:error, :shutting_down}
  end

  @spec lookup_by_path(String.t(), String.t()) ::
          {:ok, module(), metadata()} | {:error, :not_found | :shutting_down}
  def lookup_by_path(org_slug, slug) do
    if shutting_down?(), do: throw(:shutting_down)

    case :ets.lookup(@path_table, {org_slug, slug}) do
      [{{^org_slug, ^slug}, api_id}] ->
        lookup(api_id)

      [] ->
        {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  catch
    :shutting_down -> {:error, :shutting_down}
  end

  @spec unregister(Ecto.UUID.t()) :: :ok
  def unregister(api_id) do
    GenServer.call(__MODULE__, {:unregister, api_id})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Returns true if the registry is draining and rejecting new requests.
  """
  @spec shutting_down?() :: boolean()
  def shutting_down? do
    :persistent_term.get(@shutdown_flag, false)
  end

  @doc """
  Gracefully shuts down the registry:

  1. Sets a flag to reject new lookups
  2. Waits up to 30 seconds for in-flight sandbox tasks to complete
  3. Unloads all dynamic modules and clears the ETS tables

  Called from `Blackboex.Application.prep_stop/1`.
  """
  @spec shutdown() :: :ok
  def shutdown do
    Logger.info("Registry shutdown initiated, draining in-flight requests...")
    :persistent_term.put(@shutdown_flag, true)

    drain_sandbox_tasks(@drain_timeout_ms)

    # Unload all dynamically compiled modules
    unload_all_modules()

    # Clear ETS tables
    clear()

    Logger.info("Registry shutdown complete")
    :ok
  rescue
    error ->
      Logger.warning("Registry shutdown error: #{inspect(error)}")
      :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    path_table = :ets.new(@path_table, [:set, :named_table, :public, read_concurrency: true])

    # Reload synchronously to ensure APIs are available before any requests
    reload_from_db()

    {:ok, %{table: table, path_table: path_table}}
  end

  @impl true
  def handle_call({:register, api_id, module, opts}, _from, state) do
    org_slug = Keyword.get(opts, :org_slug)
    slug = Keyword.get(opts, :slug)

    metadata =
      %{
        requires_auth: Keyword.get(opts, :requires_auth, true),
        visibility: Keyword.get(opts, :visibility, "private"),
        api_id: api_id
      }

    :ets.insert(@table, {api_id, {module, metadata}})

    if org_slug && slug do
      :ets.insert(@path_table, {{org_slug, slug}, api_id})
    end

    {:reply, :ok, state}
  end

  def handle_call({:unregister, api_id}, _from, state) do
    # Find and remove path entry
    :ets.match_delete(@path_table, {:_, api_id})
    :ets.delete(@table, api_id)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    :ets.delete_all_objects(@path_table)
    {:reply, :ok, state}
  end

  defp reload_from_db do
    import Ecto.Query, warn: false

    alias Blackboex.Apis.Api
    alias Blackboex.CodeGen.Compiler
    alias Blackboex.Repo

    apis =
      Api
      |> where([a], a.status in ["compiled", "published"])
      |> preload(:organization)
      |> Repo.all()

    Enum.each(apis, &maybe_register_api/1)

    Logger.info("Registry loaded #{length(apis)} APIs from database")
  rescue
    error ->
      Logger.warning("Registry reload failed: #{inspect(error)}")
  end

  defp maybe_register_api(api) do
    alias Blackboex.CodeGen.Compiler

    module_name = Compiler.module_name_for(api)

    # If module is already loaded, just register it.
    # Otherwise, recompile from source files (modules are lost on restart).
    loaded = Code.ensure_loaded?(module_name)

    result =
      if loaded do
        {:ok, module_name}
      else
        recompile_api(api)
      end

    case result do
      {:ok, mod} ->
        metadata = %{
          requires_auth: api.requires_auth,
          visibility: api.visibility,
          api_id: api.id
        }

        :ets.insert(@table, {api.id, {mod, metadata}})
        maybe_register_path(api, mod)

      {:error, reason} ->
        Logger.warning("Failed to reload API #{api.id}: #{inspect(reason)}")
    end
  end

  defp recompile_api(api) do
    alias Blackboex.Apis
    alias Blackboex.CodeGen.Compiler

    source_files = Apis.get_source_for_compilation(api.id)

    if source_files == [] do
      {:error, :no_source_code}
    else
      Compiler.compile_files(api, source_files)
    end
  end

  defp maybe_register_path(%{organization: %{slug: slug}} = api, _module_name) do
    :ets.insert(@path_table, {{slug, api.slug}, api.id})
  end

  defp maybe_register_path(_api, _module_name), do: :ok

  defp default_metadata(api_id) do
    %{requires_auth: true, visibility: "private", api_id: api_id}
  end

  defp drain_sandbox_tasks(remaining) when remaining <= 0 do
    Logger.warning("Registry drain timeout reached, proceeding with shutdown")
  end

  defp drain_sandbox_tasks(remaining) do
    active =
      case Process.whereis(Blackboex.SandboxTaskSupervisor) do
        nil ->
          0

        pid ->
          %{active: count} = Supervisor.count_children(pid)
          count
      end

    if active > 0 do
      Logger.info("Registry drain: #{active} sandbox tasks still running, waiting...")
      Process.sleep(@drain_poll_ms)
      drain_sandbox_tasks(remaining - @drain_poll_ms)
    else
      Logger.info("Registry drain: all sandbox tasks completed")
    end
  end

  defp unload_all_modules do
    entries = :ets.tab2list(@table)

    Enum.each(entries, fn
      {_api_id, {module, _metadata}} when is_atom(module) ->
        :code.purge(module)
        :code.delete(module)

      {_api_id, module} when is_atom(module) ->
        :code.purge(module)
        :code.delete(module)

      _ ->
        :ok
    end)
  end
end
