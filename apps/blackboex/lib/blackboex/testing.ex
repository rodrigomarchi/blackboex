defmodule Blackboex.Testing do
  @moduledoc """
  Context for API testing: persists test requests, redacts headers, truncates bodies.
  """

  alias Blackboex.Repo
  alias Blackboex.Testing.{TestingQueries, TestRequest, TestSuite}

  @sensitive_headers ~w(
    authorization cookie x-api-key
    x-auth-token x-access-token x-csrf-token
    proxy-authorization set-cookie
  )
  @max_body_bytes 65_536

  # --- TestSuite CRUD ---

  @spec create_test_suite(map()) :: {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
  def create_test_suite(attrs) do
    %TestSuite{}
    |> TestSuite.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_test_suite(TestSuite.t(), map()) ::
          {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
  def update_test_suite(%TestSuite{} = suite, attrs) do
    suite
    |> TestSuite.changeset(attrs)
    |> Repo.update()
  end

  @spec list_test_suites(binary(), non_neg_integer()) :: [TestSuite.t()]
  def list_test_suites(api_id, limit \\ 10) do
    api_id
    |> TestingQueries.suites_for_api(limit)
    |> Repo.all()
  end

  @spec get_test_suite(binary()) :: {:ok, TestSuite.t()} | {:error, :not_found}
  def get_test_suite(id) do
    case Repo.get(TestSuite, id) do
      nil -> {:error, :not_found}
      suite -> {:ok, suite}
    end
  end

  @spec get_latest_test_suite(binary()) :: TestSuite.t() | nil
  def get_latest_test_suite(api_id) do
    api_id
    |> TestingQueries.latest_suite()
    |> Repo.one()
  end

  # --- TestRequest CRUD ---

  @spec create_test_request(map()) :: {:ok, TestRequest.t()} | {:error, Ecto.Changeset.t()}
  def create_test_request(attrs) do
    attrs =
      attrs
      |> maybe_redact_headers()
      |> maybe_truncate_response_body()

    %TestRequest{}
    |> TestRequest.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_test_requests(binary(), non_neg_integer()) :: [TestRequest.t()]
  def list_test_requests(api_id, limit \\ 50) do
    api_id
    |> TestingQueries.requests_for_api(limit)
    |> Repo.all()
  end

  @spec get_test_request(binary()) :: {:ok, TestRequest.t()} | {:error, :not_found}
  def get_test_request(id) do
    case Repo.get(TestRequest, id) do
      nil -> {:error, :not_found}
      tr -> {:ok, tr}
    end
  end

  @spec clear_history(binary()) :: {:ok, non_neg_integer()}
  def clear_history(api_id) do
    {count, _} =
      api_id
      |> TestingQueries.delete_requests_for_api()
      |> Repo.delete_all()

    {:ok, count}
  end

  @spec redact_headers(map()) :: map()
  def redact_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} ->
      if String.downcase(key) in @sensitive_headers do
        {key, "[REDACTED]"}
      else
        {key, value}
      end
    end)
  end

  def redact_headers(headers), do: headers

  @spec truncate_body(binary() | nil, non_neg_integer()) :: binary() | nil
  def truncate_body(body, max \\ @max_body_bytes)
  def truncate_body(nil, _max), do: nil

  def truncate_body(body, max) when is_binary(body) do
    if byte_size(body) > max do
      binary_part(body, 0, max)
    else
      body
    end
  end

  defp maybe_redact_headers(%{headers: headers} = attrs) when is_map(headers) do
    Map.put(attrs, :headers, redact_headers(headers))
  end

  defp maybe_redact_headers(attrs), do: attrs

  defp maybe_truncate_response_body(%{response_body: body} = attrs) when is_binary(body) do
    Map.put(attrs, :response_body, truncate_body(body, @max_body_bytes))
  end

  defp maybe_truncate_response_body(attrs), do: attrs
end
