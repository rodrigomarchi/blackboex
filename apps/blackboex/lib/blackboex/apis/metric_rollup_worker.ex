defmodule Blackboex.Apis.MetricRollupWorker do
  @moduledoc """
  Oban worker that aggregates invocation_logs into api_metric_rollups.

  Runs hourly via Oban Cron. Aggregates the previous hour's data.
  Idempotent via ON CONFLICT upsert. Individual API failures are logged
  but do not fail the entire job.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  import Ecto.Query

  alias Blackboex.Apis.InvocationLog
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Repo

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    {target_date, target_hour} = parse_target(args)

    start_time = NaiveDateTime.new!(target_date, Time.new!(target_hour, 0, 0))
    end_time = NaiveDateTime.add(start_time, 3600, :second)

    aggregations = aggregate_logs(start_time, end_time)

    if aggregations == [] do
      Logger.debug("MetricRollupWorker: no logs for #{target_date} hour #{target_hour}")
      :ok
    else
      upsert_rollups(aggregations, target_date, target_hour)
    end
  end

  @spec aggregate_logs(NaiveDateTime.t(), NaiveDateTime.t()) :: [map()]
  defp aggregate_logs(start_time, end_time) do
    from(l in InvocationLog,
      where: l.inserted_at >= ^start_time and l.inserted_at < ^end_time,
      group_by: l.api_id,
      select: %{
        api_id: l.api_id,
        invocations: count(l.id),
        errors: fragment("count(*) filter (where ? >= 400)", l.status_code),
        avg_duration_ms: avg(l.duration_ms),
        p95_duration_ms:
          fragment(
            "percentile_cont(0.95) within group (order by ?) filter (where ? is not null)",
            l.duration_ms,
            l.duration_ms
          ),
        unique_consumers: fragment("count(distinct ?)", l.ip_address)
      }
    )
    |> Repo.all()
  end

  @spec upsert_rollups([map()], Date.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  defp upsert_rollups(aggregations, target_date, target_hour) do
    errors =
      Enum.reduce(aggregations, [], fn agg, acc ->
        try do
          attrs = %{
            api_id: agg.api_id,
            date: target_date,
            hour: target_hour,
            invocations: agg.invocations,
            errors: agg.errors,
            avg_duration_ms: to_float(agg.avg_duration_ms),
            p95_duration_ms: to_float(agg.p95_duration_ms),
            unique_consumers: agg.unique_consumers
          }

          %MetricRollup{}
          |> MetricRollup.changeset(attrs)
          |> Repo.insert!(
            on_conflict:
              {:replace,
               [
                 :invocations,
                 :errors,
                 :avg_duration_ms,
                 :p95_duration_ms,
                 :unique_consumers,
                 :updated_at
               ]},
            conflict_target: [:api_id, :date, :hour]
          )

          acc
        rescue
          error ->
            Logger.error(
              "MetricRollupWorker: failed to upsert api_id=#{agg.api_id}: #{Exception.message(error)}"
            )

            [agg.api_id | acc]
        end
      end)

    case errors do
      [] -> :ok
      failed -> {:error, "#{length(failed)} API metric rollups failed"}
    end
  end

  @spec parse_target(map()) :: {Date.t(), non_neg_integer()}
  defp parse_target(%{"date" => date_str, "hour" => hour}) when is_integer(hour) do
    {Date.from_iso8601!(date_str), hour}
  end

  defp parse_target(_args) do
    now = NaiveDateTime.utc_now()
    prev = NaiveDateTime.add(now, -3600, :second)
    {NaiveDateTime.to_date(prev), prev.hour}
  end

  @spec to_float(Decimal.t() | float() | integer() | nil) :: float()
  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
end
