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

  @spec lookup(Ecto.UUID.t()) :: {:ok, module(), metadata()} | {:error, :not_found}
  def lookup(api_id) do
    case :ets.lookup(@table, api_id) do
      [{^api_id, {module, metadata}}] -> {:ok, module, metadata}
      # Legacy format compatibility (module without metadata)
      [{^api_id, module}] when is_atom(module) -> {:ok, module, default_metadata(api_id)}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @spec lookup_by_path(String.t(), String.t()) ::
          {:ok, module(), metadata()} | {:error, :not_found}
  def lookup_by_path(org_slug, slug) do
    case :ets.lookup(@path_table, {org_slug, slug}) do
      [{{^org_slug, ^slug}, api_id}] ->
        lookup(api_id)

      [] ->
        {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @spec unregister(Ecto.UUID.t()) :: :ok
  def unregister(api_id) do
    GenServer.call(__MODULE__, {:unregister, api_id})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
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
      |> Repo.all()
      |> Repo.preload(:organization)

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
    # Otherwise, recompile from source_code (modules are lost on restart).
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

  defp recompile_api(%{source_code: nil}), do: {:error, :no_source_code}

  defp recompile_api(api) do
    alias Blackboex.CodeGen.Compiler
    Compiler.compile(api, api.source_code)
  end

  defp maybe_register_path(%{organization: %{slug: slug}} = api, _module_name) do
    :ets.insert(@path_table, {{slug, api.slug}, api.id})
  end

  defp maybe_register_path(_api, _module_name), do: :ok

  defp default_metadata(api_id) do
    %{requires_auth: true, visibility: "private", api_id: api_id}
  end
end
