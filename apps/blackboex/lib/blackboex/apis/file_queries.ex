defmodule Blackboex.Apis.FileQueries do
  @moduledoc """
  Composable query builders for ApiFile and ApiFileRevision schemas.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.ApiFile
  alias Blackboex.Apis.ApiFileRevision

  @spec list_for_api(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_api(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id)
    |> order_by([f], asc: f.path)
  end

  @spec source_files(Ecto.UUID.t()) :: Ecto.Query.t()
  def source_files(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.file_type == "source")
    |> order_by([f], asc: f.path)
  end

  @spec test_files(Ecto.UUID.t()) :: Ecto.Query.t()
  def test_files(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.file_type == "test")
    |> order_by([f], asc: f.path)
  end

  @spec by_path(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_path(api_id, path) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.path == ^path)
  end

  @spec revisions_for_file(Ecto.UUID.t()) :: Ecto.Query.t()
  def revisions_for_file(file_id) do
    ApiFileRevision
    |> where([r], r.api_file_id == ^file_id)
    |> order_by([r], desc: r.revision_number)
  end

  @spec max_revision_number(Ecto.UUID.t()) :: Ecto.Query.t()
  def max_revision_number(file_id) do
    ApiFileRevision
    |> where([r], r.api_file_id == ^file_id)
    |> select([r], max(r.revision_number))
  end

  @spec latest_revision(Ecto.UUID.t()) :: Ecto.Query.t()
  def latest_revision(file_id) do
    ApiFileRevision
    |> where([r], r.api_file_id == ^file_id)
    |> order_by([r], desc: r.revision_number)
    |> limit(1)
  end
end
