defmodule Blackboex.Apis.DashboardQueries do
  @moduledoc """
  Aggregated queries for the dashboard.
  Provides org-level summaries, API listings with stats, and search.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.{Api, InvocationLog, MetricRollup}
  alias Blackboex.Billing.DailyUsage
  alias Blackboex.Repo

  @spec get_org_summary(Ecto.UUID.t()) :: %{
          total_apis: non_neg_integer(),
          calls_today: non_neg_integer(),
          errors_today: non_neg_integer(),
          avg_latency_today: float() | nil
        }
  def get_org_summary(org_id) do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    total_apis =
      Api
      |> where([a], a.organization_id == ^org_id)
      |> select([a], count(a.id))
      |> Repo.one()

    stats =
      InvocationLog
      |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
      |> where([l], l.inserted_at >= ^today_start)
      |> select([l], %{
        calls: count(l.id),
        errors: filter(count(l.id), l.status_code >= 400),
        avg_latency: avg(l.duration_ms)
      })
      |> Repo.one()

    avg_latency =
      case stats.avg_latency do
        nil -> nil
        %Decimal{} = d -> Decimal.to_float(d) |> Float.round(1)
        f when is_float(f) -> Float.round(f, 1)
        i when is_integer(i) -> i * 1.0
      end

    %{
      total_apis: total_apis,
      calls_today: stats.calls,
      errors_today: stats.errors,
      avg_latency_today: avg_latency
    }
  end

  @spec list_apis_with_stats(Ecto.UUID.t(), keyword()) :: [
          %{
            api: Api.t(),
            calls_24h: non_neg_integer(),
            errors_24h: non_neg_integer(),
            avg_latency: float() | nil
          }
        ]
  def list_apis_with_stats(org_id, opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -86_400)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)

    query =
      Api
      |> where([a], a.organization_id == ^org_id)
      |> maybe_search(search)
      |> join(:left, [a], l in InvocationLog, on: l.api_id == a.id and l.inserted_at >= ^since)
      |> group_by([a, l], a.id)
      |> select([a, l], %{
        api: a,
        calls_24h: count(l.id),
        errors_24h: filter(count(l.id), l.status_code >= 400),
        avg_latency: avg(l.duration_ms)
      })
      |> order_by([a], desc: a.inserted_at)
      |> limit(^limit)

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | avg_latency: normalize_latency(row.avg_latency)}
    end)
  end

  @spec search_apis(Ecto.UUID.t(), String.t()) :: [Api.t()]
  def search_apis(org_id, query) do
    Api
    |> where([a], a.organization_id == ^org_id)
    |> maybe_search(query)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @spec get_dashboard_metrics(Ecto.UUID.t(), String.t()) :: %{
          calls_series: [%{label: String.t(), value: non_neg_integer()}],
          errors_series: [%{label: String.t(), value: non_neg_integer()}],
          latency_avg_series: [%{label: String.t(), value: float()}],
          latency_p95_series: [%{label: String.t(), value: float()}],
          top_apis: [%{name: String.t(), calls: non_neg_integer(), avg_latency: float()}]
        }
  def get_dashboard_metrics(org_id, period \\ "24h") do
    {start_date, group_by} = period_config(period)

    rollups =
      MetricRollup
      |> join(:inner, [r], a in Api, on: r.api_id == a.id)
      |> where([r, a], a.organization_id == ^org_id)
      |> where([r], r.date >= ^start_date)
      |> select_series(group_by)
      |> Repo.all()

    top_apis =
      MetricRollup
      |> join(:inner, [r], a in Api, on: r.api_id == a.id)
      |> where([r, a], a.organization_id == ^org_id)
      |> where([r], r.date >= ^start_date)
      |> group_by([r, a], [a.id, a.name])
      |> select([r, a], %{
        name: a.name,
        calls: sum(r.invocations),
        avg_latency:
          fragment(
            "CASE WHEN SUM(?) > 0 THEN SUM(? * ?) / SUM(?) ELSE 0 END",
            r.invocations,
            r.avg_duration_ms,
            r.invocations,
            r.invocations
          )
      })
      |> order_by([r], desc: sum(r.invocations))
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn row ->
        %{
          name: row.name,
          calls: row.calls || 0,
          avg_latency: normalize_latency(row.avg_latency) || 0.0
        }
      end)

    %{
      calls_series: build_series(rollups, start_date, group_by, :calls),
      errors_series: build_series(rollups, start_date, group_by, :errors),
      latency_avg_series: build_series(rollups, start_date, group_by, :avg_latency),
      latency_p95_series: build_series(rollups, start_date, group_by, :p95_latency),
      top_apis: top_apis
    }
  end

  @spec get_llm_usage_series(Ecto.UUID.t(), String.t()) :: %{
          generations_series: [%{label: String.t(), value: non_neg_integer()}],
          tokens_in_total: non_neg_integer(),
          tokens_out_total: non_neg_integer(),
          cost_total_cents: non_neg_integer()
        }
  def get_llm_usage_series(org_id, period \\ "30d") do
    days =
      case period do
        "24h" -> 1
        "7d" -> 7
        "30d" -> 30
        _ -> 30
      end

    start_date = Date.add(Date.utc_today(), -days)

    daily_data =
      DailyUsage
      |> where([d], d.organization_id == ^org_id and d.date >= ^start_date)
      |> order_by([d], d.date)
      |> Repo.all()

    generations_series = build_daily_series(daily_data, start_date, :llm_generations)

    %{
      generations_series: generations_series,
      tokens_in_total: daily_data |> Enum.map(&(&1.tokens_input || 0)) |> Enum.sum(),
      tokens_out_total: daily_data |> Enum.map(&(&1.tokens_output || 0)) |> Enum.sum(),
      cost_total_cents: daily_data |> Enum.map(&(&1.llm_cost_cents || 0)) |> Enum.sum()
    }
  end

  # -- Period configuration --

  @spec period_config(String.t()) :: {Date.t(), :hourly | :daily}
  # "24h" renamed internally to "Today" — shows today's hourly data only
  defp period_config("24h"), do: {Date.utc_today(), :hourly}
  defp period_config("7d"), do: {Date.add(Date.utc_today(), -6), :daily}
  defp period_config("30d"), do: {Date.add(Date.utc_today(), -29), :daily}
  defp period_config(_), do: {Date.add(Date.utc_today(), -29), :daily}

  # -- Query helpers --

  defp select_series(query, :hourly) do
    query
    |> group_by([r], r.hour)
    |> order_by([r], r.hour)
    |> select([r, a], %{
      bucket: r.hour,
      calls: sum(r.invocations),
      errors: sum(r.errors),
      avg_latency:
        fragment(
          "CASE WHEN SUM(?) > 0 THEN SUM(? * ?) / SUM(?) ELSE 0 END",
          r.invocations,
          r.avg_duration_ms,
          r.invocations,
          r.invocations
        ),
      p95_latency:
        fragment(
          "CASE WHEN SUM(?) > 0 THEN SUM(? * ?) / SUM(?) ELSE 0 END",
          r.invocations,
          r.p95_duration_ms,
          r.invocations,
          r.invocations
        )
    })
  end

  defp select_series(query, :daily) do
    query
    |> group_by([r], r.date)
    |> order_by([r], r.date)
    |> select([r, a], %{
      bucket: r.date,
      calls: sum(r.invocations),
      errors: sum(r.errors),
      avg_latency:
        fragment(
          "CASE WHEN SUM(?) > 0 THEN SUM(? * ?) / SUM(?) ELSE 0 END",
          r.invocations,
          r.avg_duration_ms,
          r.invocations,
          r.invocations
        ),
      p95_latency:
        fragment(
          "CASE WHEN SUM(?) > 0 THEN SUM(? * ?) / SUM(?) ELSE 0 END",
          r.invocations,
          r.p95_duration_ms,
          r.invocations,
          r.invocations
        )
    })
  end

  # -- Series building with gap filling --

  defp build_series(rollups, _start_date, :hourly, field) do
    lookup = Map.new(rollups, fn r -> {r.bucket, safe_number(Map.get(r, field))} end)

    Enum.map(0..23, fn hour ->
      %{
        label: hour |> Integer.to_string() |> String.pad_leading(2, "0"),
        value: Map.get(lookup, hour, 0)
      }
    end)
  end

  defp build_series(rollups, start_date, :daily, field) do
    today = Date.utc_today()
    lookup = Map.new(rollups, fn r -> {r.bucket, safe_number(Map.get(r, field))} end)

    Date.range(start_date, today)
    |> Enum.map(fn date ->
      %{
        label: Calendar.strftime(date, "%b %d"),
        value: Map.get(lookup, date, 0)
      }
    end)
  end

  defp build_daily_series(daily_data, start_date, field) do
    today = Date.utc_today()
    lookup = Map.new(daily_data, fn d -> {d.date, Map.get(d, field) || 0} end)

    Date.range(start_date, today)
    |> Enum.map(fn date ->
      %{
        label: Calendar.strftime(date, "%b %d"),
        value: Map.get(lookup, date, 0)
      }
    end)
  end

  defp safe_number(nil), do: 0
  defp safe_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_number(n) when is_number(n), do: n
  defp safe_number(_), do: 0

  defp maybe_search(queryable, nil), do: queryable
  defp maybe_search(queryable, ""), do: queryable

  defp maybe_search(queryable, search) when is_binary(search) do
    pattern = "%#{sanitize_like(search)}%"
    where(queryable, [a], ilike(a.name, ^pattern) or ilike(a.description, ^pattern))
  end

  defp sanitize_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp normalize_latency(nil), do: nil
  defp normalize_latency(%Decimal{} = d), do: Decimal.to_float(d) |> Float.round(1)
  defp normalize_latency(f) when is_float(f), do: Float.round(f, 1)
  defp normalize_latency(i) when is_integer(i), do: i * 1.0
end
