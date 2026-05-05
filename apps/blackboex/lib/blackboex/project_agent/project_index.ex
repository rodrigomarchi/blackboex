defmodule Blackboex.ProjectAgent.ProjectIndex do
  @moduledoc """
  Lightweight metadata-only index of a Project's artifacts (`Apis`, `Flows`,
  `Pages`, `Playgrounds`) used as the **stable** prompt-cache prefix for
  the Project Planner.

  Cached in ETS keyed by `(project_id, max_artifact_updated_at)` so the
  cache auto-invalidates whenever any artifact mutates. The cache key is
  also embedded as a stable token in the rendered digest text so a stale
  cached prefix on Anthropic's side cannot resurrect old data — the
  upstream cache key is content-addressed by the digest text itself.

  Only **metadata** is included (id, name/title, slug, kind). Source code
  / definitions / page contents are out of scope here — they belong to a
  per-task expansion the Planner can request only when needed.
  """

  alias Blackboex.{Apis, Flows, Pages, Playgrounds}
  alias Blackboex.Projects.Project

  @table :project_agent_project_index_cache

  @typedoc "Compact metadata row for any artifact kind."
  @type artifact_row :: %{required(:id) => Ecto.UUID.t(), required(:name) => String.t()}

  @typedoc "Project digest passed to `to_text/1` and embedded in the cache prefix."
  @type t :: %{
          required(:project_id) => Ecto.UUID.t(),
          required(:cache_key) => String.t(),
          required(:apis) => [artifact_row()],
          required(:flows) => [artifact_row()],
          required(:pages) => [artifact_row()],
          required(:playgrounds) => [artifact_row()]
        }

  @doc """
  Builds the digest for `project`. The result is cached in ETS keyed by
  `(project_id, max_artifact_updated_at)` so subsequent calls are O(1) as
  long as no artifact has mutated.
  """
  @spec build(Project.t()) :: t()
  def build(%Project{id: project_id} = project) do
    ensure_table()
    apis = list_apis(project)
    flows = list_flows(project)
    pages = list_pages(project)
    playgrounds = list_playgrounds(project)

    max_updated = max_updated_at([apis, flows, pages, playgrounds])
    cache_key = compose_cache_key(project_id, max_updated)

    case :ets.lookup(@table, {project_id, cache_key}) do
      [{_, cached}] ->
        cached

      [] ->
        digest = %{
          project_id: project_id,
          cache_key: cache_key,
          apis: rows(apis, :name),
          flows: rows(flows, :name),
          pages: rows(pages, :title),
          playgrounds: rows(playgrounds, :name)
        }

        :ets.insert(@table, {{project_id, cache_key}, digest})
        digest
    end
  end

  @doc """
  Renders the digest as a stable plain-text block suitable for use as the
  cacheable prefix of a Planner prompt. The format is intentionally
  deterministic so the same project + same `max_updated_at` produces the
  same byte sequence (a prerequisite for prompt-cache hits).
  """
  @spec to_text(t()) :: String.t()
  def to_text(%{
        project_id: project_id,
        cache_key: cache_key,
        apis: apis,
        flows: flows,
        pages: pages,
        playgrounds: playgrounds
      }) do
    [
      "Project ID: ",
      project_id,
      "\n",
      "Index cache key: ",
      cache_key,
      "\n\n",
      section("APIs", apis),
      section("Flows", flows),
      section("Pages", pages),
      section("Playgrounds", playgrounds)
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Drops the ETS cache. Test-only helper; production code should rely on
  the auto-invalidating composite cache key.
  """
  @spec flush_cache() :: :ok
  def flush_cache do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  # ── Internals ──────────────────────────────────────────────────

  @spec list_apis(Project.t()) :: list()
  defp list_apis(%Project{id: id}) do
    Apis.list_apis_for_project(id)
  rescue
    _ -> []
  end

  @spec list_flows(Project.t()) :: list()
  defp list_flows(%Project{id: id}) do
    Flows.list_flows_for_project(id)
  rescue
    _ -> []
  end

  @spec list_pages(Project.t()) :: list()
  defp list_pages(%Project{id: id}) do
    Pages.list_pages(id)
  rescue
    _ -> []
  end

  @spec list_playgrounds(Project.t()) :: list()
  defp list_playgrounds(%Project{id: id}) do
    Playgrounds.list_playgrounds(id)
  rescue
    _ -> []
  end

  @spec rows([struct()], atom()) :: [artifact_row()]
  defp rows(structs, name_key) when is_list(structs) do
    Enum.map(structs, fn s ->
      %{id: Map.get(s, :id), name: to_string(Map.get(s, name_key) || "")}
    end)
  end

  @spec section(String.t(), [artifact_row()]) :: iolist()
  defp section(_title, []), do: []

  defp section(title, rows) when is_list(rows) do
    [
      "## ",
      title,
      "\n",
      Enum.map(rows, fn %{id: id, name: name} -> ["- ", name, " (", to_string(id), ")\n"] end),
      "\n"
    ]
  end

  @spec max_updated_at([list()]) :: String.t() | nil
  defp max_updated_at(lists) do
    lists
    |> List.flatten()
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&iso_string/1)
    |> Enum.max(fn -> nil end)
  end

  @spec iso_string(DateTime.t() | NaiveDateTime.t()) :: String.t()
  defp iso_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso_string(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  @spec compose_cache_key(Ecto.UUID.t(), String.t() | nil) :: String.t()
  defp compose_cache_key(project_id, nil), do: "#{project_id}:empty"
  defp compose_cache_key(project_id, ts) when is_binary(ts), do: "#{project_id}:#{ts}"

  @spec ensure_table() :: :ok
  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        # `:public` so callers from any process can read/write. `:set` for
        # exact-key dedup. ETS table outlives caller processes (it's owned
        # by whoever creates it first; since this module has no GenServer,
        # the first caller's process owns the table — acceptable because
        # the cache is best-effort and a table loss on owner death just
        # forces a rebuild on next call).
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end
end
