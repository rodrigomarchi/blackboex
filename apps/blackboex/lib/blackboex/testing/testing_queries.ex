defmodule Blackboex.Testing.TestingQueries do
  @moduledoc """
  Composable query builders for TestSuite and TestRequest schemas.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Testing.{TestRequest, TestSuite}

  @spec suites_for_api(binary(), pos_integer()) :: Ecto.Query.t()
  def suites_for_api(api_id, limit) do
    TestSuite
    |> where([ts], ts.api_id == ^api_id)
    |> order_by([ts], desc: ts.inserted_at, desc: ts.id)
    |> limit(^limit)
  end

  @spec latest_suite(binary()) :: Ecto.Query.t()
  def latest_suite(api_id) do
    TestSuite
    |> where([ts], ts.api_id == ^api_id)
    |> order_by([ts], desc: ts.inserted_at, desc: ts.id)
    |> limit(1)
  end

  @spec requests_for_api(binary(), pos_integer()) :: Ecto.Query.t()
  def requests_for_api(api_id, limit) do
    TestRequest
    |> where([tr], tr.api_id == ^api_id)
    |> order_by([tr], desc: tr.inserted_at, desc: tr.id)
    |> limit(^limit)
  end

  @spec delete_requests_for_api(binary()) :: Ecto.Query.t()
  def delete_requests_for_api(api_id) do
    TestRequest
    |> where([tr], tr.api_id == ^api_id)
  end
end
