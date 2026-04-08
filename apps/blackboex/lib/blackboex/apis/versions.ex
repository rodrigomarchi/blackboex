defmodule Blackboex.Apis.Versions do
  @moduledoc """
  Sub-context for API versioning.

  Manages ApiVersion snapshots, diff summaries, and rollback operations.
  """

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiVersion
  alias Blackboex.Apis.Files
  alias Blackboex.Apis.VersionQueries
  alias Blackboex.CodeGen.DiffEngine
  alias Blackboex.Repo

  # ── Public API ──────────────────────────────────────────────

  @spec create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_version(%Api{} = api, attrs) do
    file_snapshots = attrs[:file_snapshots] || Files.build_file_snapshots(api.id)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:next_number, fn repo, changes ->
      next_version_number(repo, changes, api.id)
    end)
    |> Ecto.Multi.run(:diff_summary, fn _repo, _changes ->
      {:ok, compute_version_diff_summary(api.id, file_snapshots)}
    end)
    |> Ecto.Multi.insert(:version, fn %{next_number: number, diff_summary: summary} ->
      ApiVersion.changeset(
        %ApiVersion{},
        Map.merge(attrs, %{
          api_id: api.id,
          version_number: number,
          file_snapshots: file_snapshots,
          diff_summary: summary
        })
      )
    end)
    |> Repo.transaction()
    |> unwrap_version_transaction()
  end

  @spec list_versions(Ecto.UUID.t()) :: [ApiVersion.t()]
  def list_versions(api_id) do
    api_id |> VersionQueries.list_for_api() |> Repo.all()
  end

  @spec get_version(Ecto.UUID.t(), integer()) :: ApiVersion.t() | nil
  def get_version(api_id, version_number) do
    api_id |> VersionQueries.by_number(version_number) |> Repo.one()
  end

  @spec published_version(Ecto.UUID.t()) :: ApiVersion.t() | nil
  def published_version(api_id) do
    api_id |> VersionQueries.latest_published() |> Repo.one()
  end

  @spec get_latest_version(Api.t()) :: ApiVersion.t() | nil
  def get_latest_version(%Api{id: api_id}) do
    api_id |> VersionQueries.latest() |> Repo.one()
  end

  @spec rollback_to_version(Api.t(), integer(), integer() | nil) ::
          {:ok, ApiVersion.t()} | {:error, :version_not_found | Ecto.Changeset.t()}
  def rollback_to_version(%Api{} = api, target_version_number, created_by_id \\ nil) do
    case get_version(api.id, target_version_number) do
      nil ->
        {:error, :version_not_found}

      target ->
        restore_files_from_snapshots(api, target.file_snapshots, created_by_id)

        create_version(api, %{
          source: "rollback",
          prompt: "Rollback to version #{target_version_number}",
          created_by_id: created_by_id
        })
    end
  end

  # ── Private ─────────────────────────────────────────────────

  defp next_version_number(repo, _changes, api_id) do
    result = api_id |> VersionQueries.max_version_number() |> repo.one()
    {:ok, (result || 0) + 1}
  end

  defp compute_version_diff_summary(api_id, current_snapshots) do
    latest = api_id |> VersionQueries.latest() |> Repo.one()

    case latest do
      nil -> nil
      prev -> diff_snapshots(prev.file_snapshots, current_snapshots)
    end
  end

  defp diff_snapshots(prev_snapshots, curr_snapshots) do
    prev_map = snapshots_to_map(prev_snapshots)
    curr_map = snapshots_to_map(curr_snapshots)

    all_paths = (Map.keys(curr_map) ++ Map.keys(prev_map)) |> Enum.uniq()

    changes = Enum.flat_map(all_paths, &diff_single_path(&1, prev_map, curr_map))

    if changes == [], do: "No changes", else: Enum.join(changes, "\n")
  end

  defp snapshots_to_map(snapshots) do
    Map.new(snapshots, &{&1["path"] || &1[:path], &1["content"] || &1[:content]})
  end

  defp diff_single_path(path, prev_map, curr_map) do
    prev_content = Map.get(prev_map, path)
    curr_content = Map.get(curr_map, path)

    cond do
      is_nil(prev_content) ->
        ["+ #{path} (new file)"]

      is_nil(curr_content) ->
        ["- #{path} (deleted)"]

      prev_content != curr_content ->
        diff = DiffEngine.compute_diff(prev_content, curr_content)
        ["~ #{path}: #{DiffEngine.format_diff_summary(diff)}"]

      true ->
        []
    end
  end

  defp unwrap_version_transaction({:ok, %{version: version}}), do: {:ok, version}
  defp unwrap_version_transaction({:error, :version, changeset, _}), do: {:error, changeset}
  defp unwrap_version_transaction({:error, _step, reason, _}), do: {:error, reason}

  defp restore_files_from_snapshots(api, snapshots, created_by_id) do
    Enum.each(snapshots, fn snapshot ->
      path = snapshot["path"] || snapshot[:path]
      content = snapshot["content"] || snapshot[:content]

      case Files.get_file(api.id, path) do
        nil ->
          Files.create_file(api, %{
            path: path,
            content: content,
            file_type: Files.infer_file_type(path),
            source: "rollback",
            created_by_id: created_by_id
          })

        existing ->
          Files.update_file_content(existing, content, %{
            source: "rollback",
            message: "Restored from version snapshot",
            created_by_id: created_by_id
          })
      end
    end)

    snapshot_paths = Enum.map(snapshots, &(&1["path"] || &1[:path]))
    current_files = Files.list_files(api.id)

    Enum.each(current_files, fn file ->
      unless file.path in snapshot_paths, do: Files.delete_file(file)
    end)
  end
end
