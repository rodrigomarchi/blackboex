defmodule Blackboex.Apis.VersionQueries do
  @moduledoc """
  Composable query builders for ApiVersion schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.ApiVersion

  @spec list_for_api(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_api(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
  end

  @spec by_number(Ecto.UUID.t(), integer()) :: Ecto.Query.t()
  def by_number(api_id, version_number) do
    ApiVersion
    |> where([v], v.api_id == ^api_id and v.version_number == ^version_number)
  end

  @spec latest_published(Ecto.UUID.t()) :: Ecto.Query.t()
  def latest_published(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id and v.source == "publish")
    |> order_by([v], desc: v.version_number)
    |> limit(1)
  end

  @spec latest(Ecto.UUID.t()) :: Ecto.Query.t()
  def latest(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
    |> limit(1)
  end

  @spec max_version_number(Ecto.UUID.t()) :: Ecto.Query.t()
  def max_version_number(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> select([v], max(v.version_number))
  end

  @spec count_labeled_today(Ecto.UUID.t(), Date.t()) :: Ecto.Query.t()
  def count_labeled_today(api_id, date) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> where([v], fragment("?::date", v.inserted_at) == ^date)
    |> where([v], not is_nil(v.version_label))
  end
end
