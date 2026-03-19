defmodule Blackboex.Apis.Analytics do
  @moduledoc """
  Analytics queries for API invocation metrics.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.InvocationLog
  alias Blackboex.Repo

  require Logger

  @spec log_invocation(map()) :: :ok
  def log_invocation(attrs) do
    case Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
           persist_log(attrs)
         end) do
      {:ok, _pid} -> :ok
      {:error, reason} -> Logger.warning("Failed to spawn logging task: #{inspect(reason)}")
    end

    :ok
  end

  defp persist_log(attrs) do
    case %InvocationLog{} |> InvocationLog.changeset(attrs) |> Repo.insert() do
      {:ok, _log} -> :ok
      {:error, changeset} -> Logger.warning("Failed to log invocation: #{inspect(changeset)}")
    end
  end

  @spec invocations_count(Ecto.UUID.t(), keyword()) :: non_neg_integer()
  def invocations_count(api_id, opts \\ []) do
    api_id
    |> base_query(opts)
    |> select([l], count(l.id))
    |> Repo.one()
  end

  @spec success_rate(Ecto.UUID.t(), keyword()) :: float()
  def success_rate(api_id, opts \\ []) do
    query = base_query(api_id, opts)

    total = query |> select([l], count(l.id)) |> Repo.one()

    if total == 0 do
      0.0
    else
      successes =
        query
        |> where([l], l.status_code >= 200 and l.status_code < 300)
        |> select([l], count(l.id))
        |> Repo.one()

      Float.round(successes / total * 100, 1)
    end
  end

  @spec avg_latency(Ecto.UUID.t(), keyword()) :: float()
  def avg_latency(api_id, opts \\ []) do
    result =
      api_id
      |> base_query(opts)
      |> select([l], avg(l.duration_ms))
      |> Repo.one()

    case result do
      nil -> 0.0
      %Decimal{} = d -> Decimal.to_float(d) |> Float.round(1)
      f when is_float(f) -> Float.round(f, 1)
    end
  end

  defp base_query(api_id, opts) do
    period = Keyword.get(opts, :period, :all)

    query = InvocationLog |> where([l], l.api_id == ^api_id)

    case period do
      :all ->
        query

      :day ->
        since = DateTime.add(DateTime.utc_now(), -86_400)
        where(query, [l], l.inserted_at >= ^since)

      :week ->
        since = DateTime.add(DateTime.utc_now(), -604_800)
        where(query, [l], l.inserted_at >= ^since)

      :month ->
        since = DateTime.add(DateTime.utc_now(), -2_592_000)
        where(query, [l], l.inserted_at >= ^since)
    end
  end
end
