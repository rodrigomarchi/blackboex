defmodule Blackboex.Apis.Files do
  @moduledoc """
  Sub-context for API file management.

  Handles CRUD operations on ApiFiles and their revision history.
  """

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiFile
  alias Blackboex.Apis.ApiFileRevision
  alias Blackboex.Apis.FileQueries
  alias Blackboex.Apis.VirtualFile
  alias Blackboex.CodeGen.DiffEngine
  alias Blackboex.Repo

  # ── Public API ──────────────────────────────────────────────

  @spec list_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_files(api_id) do
    api_id |> FileQueries.list_for_api() |> Repo.all()
  end

  @spec list_files_with_virtual(Api.t()) :: [map()]
  def list_files_with_virtual(%Api{} = api) do
    db_files = list_files(api.id) |> Enum.map(&Map.put(&1, :read_only, false))
    virtual_files = VirtualFile.build(api)
    db_files ++ virtual_files
  end

  @spec list_source_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_source_files(api_id) do
    api_id |> FileQueries.source_files() |> Repo.all()
  end

  @spec list_test_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_test_files(api_id) do
    api_id |> FileQueries.test_files() |> Repo.all()
  end

  @spec get_file(Ecto.UUID.t(), String.t()) :: ApiFile.t() | nil
  def get_file(api_id, path) do
    api_id |> FileQueries.by_path(path) |> Repo.one()
  end

  @spec get_file!(Ecto.UUID.t()) :: ApiFile.t()
  def get_file!(file_id) do
    Repo.get!(ApiFile, file_id)
  end

  @spec create_file(Api.t(), map()) :: {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def create_file(%Api{} = api, attrs) do
    Repo.transaction(fn ->
      file =
        %ApiFile{}
        |> ApiFile.changeset(Map.put(attrs, :api_id, api.id))
        |> Repo.insert!()

      create_initial_revision(
        file,
        attrs[:content],
        attrs[:source] || "generation",
        attrs[:created_by_id]
      )

      file
    end)
  end

  @spec update_file_content(ApiFile.t(), String.t(), map()) ::
          {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def update_file_content(%ApiFile{} = file, new_content, opts \\ %{}) do
    old_content = file.content

    Repo.transaction(fn ->
      updated_file =
        file
        |> Ecto.Changeset.change(content: new_content)
        |> Repo.update!()

      diff = if old_content, do: DiffEngine.compute_diff(old_content, new_content), else: nil

      create_revision(
        file,
        new_content,
        diff && DiffEngine.format_diff_summary(diff),
        opts[:source] || "manual_edit",
        opts[:message],
        opts[:created_by_id]
      )

      updated_file
    end)
  end

  @spec delete_file(ApiFile.t()) :: {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def delete_file(%ApiFile{} = file) do
    Repo.delete(file)
  end

  @spec list_file_revisions(Ecto.UUID.t()) :: [ApiFileRevision.t()]
  def list_file_revisions(file_id) do
    file_id |> FileQueries.revisions_for_file() |> Repo.all()
  end

  @doc """
  Upserts files for an API from a list of `%{path, content, file_type}` maps.
  Creates new files or updates existing ones, creating revisions for each change.
  Returns the list of upserted ApiFile records.
  """
  @spec upsert_files(Api.t(), [map()], map()) :: {:ok, [ApiFile.t()]}
  def upsert_files(%Api{} = api, file_maps, opts \\ %{}) do
    Repo.transaction(fn ->
      Enum.map(file_maps, &upsert_single_file(api, &1, opts))
    end)
  end

  @doc """
  Builds file_snapshots for the current state of all files in an API.
  Used when creating ApiVersions.
  """
  @spec build_file_snapshots(Ecto.UUID.t()) :: [map()]
  def build_file_snapshots(api_id) do
    files = list_files(api_id)

    Enum.map(files, fn file ->
      latest_rev = file.id |> FileQueries.latest_revision() |> Repo.one()

      %{
        path: file.path,
        content: file.content,
        file_id: file.id,
        revision_number: if(latest_rev, do: latest_rev.revision_number, else: 1)
      }
    end)
  end

  @doc """
  Returns the source code for compilation as a list of `%{path: String.t(), content: String.t()}`.
  """
  @spec get_source_for_compilation(Ecto.UUID.t()) :: [%{path: String.t(), content: String.t()}]
  def get_source_for_compilation(api_id) do
    api_id
    |> list_source_files()
    |> Enum.map(&%{path: &1.path, content: &1.content || ""})
  end

  @doc """
  Returns the test code for testing as a list of `%{path: String.t(), content: String.t()}`.
  """
  @spec get_tests_for_running(Ecto.UUID.t()) :: [%{path: String.t(), content: String.t()}]
  def get_tests_for_running(api_id) do
    api_id
    |> list_test_files()
    |> Enum.map(&%{path: &1.path, content: &1.content || ""})
  end

  @doc """
  Infers file type from path prefix.
  """
  @spec infer_file_type(String.t()) :: String.t()
  def infer_file_type(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/test") -> "test"
      String.starts_with?(path, "/src") -> "source"
      true -> "source"
    end
  end

  # ── Private ─────────────────────────────────────────────────

  defp create_initial_revision(file, content, source, created_by_id) do
    %ApiFileRevision{}
    |> ApiFileRevision.changeset(%{
      api_file_id: file.id,
      content: content || "",
      source: source,
      message: "Initial file creation",
      revision_number: 1,
      created_by_id: created_by_id
    })
    |> Repo.insert!()
  end

  defp create_revision(file, content, diff, source, message, created_by_id) do
    next_rev = file.id |> FileQueries.max_revision_number() |> Repo.one()
    next_rev = (next_rev || 0) + 1

    %ApiFileRevision{}
    |> ApiFileRevision.changeset(%{
      api_file_id: file.id,
      content: content,
      diff: diff,
      source: source,
      message: message,
      revision_number: next_rev,
      created_by_id: created_by_id
    })
    |> Repo.insert!()
  end

  defp upsert_single_file(api, file_map, opts) do
    path = file_map[:path] || file_map["path"]
    content = file_map[:content] || file_map["content"]
    file_type = file_map[:file_type] || file_map["file_type"] || infer_file_type(path)
    source = opts[:source] || "generation"

    case get_file(api.id, path) do
      nil ->
        {:ok, file} =
          create_file(api, %{
            path: path,
            content: content,
            file_type: file_type,
            source: source,
            created_by_id: opts[:created_by_id]
          })

        file

      existing ->
        {:ok, file} =
          update_file_content(existing, content, %{
            source: source,
            message: opts[:message],
            created_by_id: opts[:created_by_id]
          })

        file
    end
  end
end
