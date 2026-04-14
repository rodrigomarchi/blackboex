defmodule Blackboex.Apis.DashboardQueries do
  @moduledoc """
  Aggregated queries for the dashboard.
  Provides org-level summaries, API listings with stats, and search.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.{Api, ApiKey, InvocationLog, MetricRollup}
  alias Blackboex.Billing.DailyUsage
  alias Blackboex.Conversations.{Conversation, Run}
  alias Blackboex.FlowExecutions.FlowExecution
  alias Blackboex.Flows.Flow
  alias Blackboex.LLM.Usage, as: LlmUsage
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

  @spec list_apis_with_stats_for_project(Ecto.UUID.t(), keyword()) :: [
          %{
            api: Api.t(),
            calls_24h: non_neg_integer(),
            errors_24h: non_neg_integer(),
            avg_latency: float() | nil
          }
        ]
  def list_apis_with_stats_for_project(project_id, opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -86_400)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)

    query =
      Api
      |> where([a], a.project_id == ^project_id)
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

  @spec get_overview_summary(Ecto.UUID.t()) :: map()
  def get_overview_summary(org_id) do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    month_start = Date.utc_today() |> Date.beginning_of_month()

    total_apis =
      Api
      |> where([a], a.organization_id == ^org_id)
      |> select([a], count(a.id))
      |> Repo.one()

    active_apis =
      Api
      |> where([a], a.organization_id == ^org_id and a.status == "published")
      |> select([a], count(a.id))
      |> Repo.one()

    total_api_keys =
      ApiKey
      |> where([k], k.organization_id == ^org_id)
      |> select([k], count(k.id))
      |> Repo.one()

    total_flows =
      Flow
      |> where([f], f.organization_id == ^org_id)
      |> select([f], count(f.id))
      |> Repo.one()

    active_flows =
      Flow
      |> where([f], f.organization_id == ^org_id and f.status == "active")
      |> select([f], count(f.id))
      |> Repo.one()

    api_calls_today =
      InvocationLog
      |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
      |> where([l], l.inserted_at >= ^today_start)
      |> select([l], count(l.id))
      |> Repo.one()

    flow_execs_today =
      FlowExecution
      |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^today_start)
      |> select([e], count(e.id))
      |> Repo.one()

    total_conversations =
      Conversation
      |> where([c], c.organization_id == ^org_id)
      |> select([c], count(c.id))
      |> Repo.one()

    llm_cost_month =
      DailyUsage
      |> where([d], d.organization_id == ^org_id and d.date >= ^month_start)
      |> select([d], sum(d.llm_cost_cents))
      |> Repo.one() || 0

    errors_today =
      InvocationLog
      |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
      |> where([l], l.inserted_at >= ^today_start and l.status_code >= 400)
      |> select([l], count(l.id))
      |> Repo.one()

    %{
      total_apis: total_apis,
      total_flows: total_flows,
      total_api_keys: total_api_keys,
      active_apis: active_apis,
      active_flows: active_flows,
      total_executions_today: api_calls_today + flow_execs_today,
      total_conversations: total_conversations,
      llm_cost_month_cents: llm_cost_month,
      errors_today: errors_today
    }
  end

  @spec get_flow_metrics(Ecto.UUID.t(), String.t()) :: %{
          total_executions: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          avg_duration_ms: float() | nil,
          success_rate: float(),
          executions_series: [%{label: String.t(), value: non_neg_integer()}],
          failures_series: [%{label: String.t(), value: non_neg_integer()}],
          duration_series: [%{label: String.t(), value: float()}],
          top_flows: [
            %{
              name: String.t(),
              executions: non_neg_integer(),
              avg_duration: float() | nil,
              success_rate: float()
            }
          ]
        }
  def get_flow_metrics(org_id, period \\ "24h") do
    {start_date, group_by} = period_config(period)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    stats =
      FlowExecution
      |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^start_dt)
      |> select([e], %{
        total: count(e.id),
        completed: filter(count(e.id), e.status == "completed"),
        failed: filter(count(e.id), e.status == "failed"),
        avg_duration: avg(e.duration_ms)
      })
      |> Repo.one()

    success_rate =
      if stats.total > 0,
        do: Float.round(stats.completed / stats.total * 100, 1),
        else: 0.0

    series_data = flow_series_data(org_id, start_dt, group_by)

    top_flows =
      FlowExecution
      |> join(:inner, [e], f in Flow, on: e.flow_id == f.id)
      |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^start_dt)
      |> group_by([e, f], [f.id, f.name])
      |> select([e, f], %{
        name: f.name,
        executions: count(e.id),
        avg_duration: avg(e.duration_ms),
        completed: filter(count(e.id), e.status == "completed"),
        total: count(e.id)
      })
      |> order_by([e], desc: count(e.id))
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn row ->
        rate = if row.total > 0, do: Float.round(row.completed / row.total * 100, 1), else: 0.0

        %{
          name: row.name,
          executions: row.executions,
          avg_duration: normalize_latency(row.avg_duration),
          success_rate: rate
        }
      end)

    %{
      total_executions: stats.total,
      completed: stats.completed,
      failed: stats.failed,
      avg_duration_ms: normalize_latency(stats.avg_duration),
      success_rate: success_rate,
      executions_series: build_flow_series(series_data, start_date, group_by, :executions),
      failures_series: build_flow_series(series_data, start_date, group_by, :failures),
      duration_series: build_flow_series(series_data, start_date, group_by, :avg_duration),
      top_flows: top_flows
    }
  end

  @spec get_usage_metrics(Ecto.UUID.t(), String.t()) :: %{
          api_invocations_series: [%{label: String.t(), value: non_neg_integer()}],
          api_invocations_total: non_neg_integer(),
          generations_series: [%{label: String.t(), value: non_neg_integer()}],
          llm_generations_total: non_neg_integer(),
          tokens_in_series: [%{label: String.t(), value: non_neg_integer()}],
          tokens_out_series: [%{label: String.t(), value: non_neg_integer()}],
          tokens_in_total: non_neg_integer(),
          tokens_out_total: non_neg_integer(),
          cost_series: [%{label: String.t(), value: float()}],
          cost_total_cents: non_neg_integer()
        }
  def get_usage_metrics(org_id, period \\ "30d") do
    {start_date, daily_data} = load_daily_usage(org_id, period)
    build_usage_result(daily_data, start_date)
  end

  defp load_daily_usage(org_id, period) do
    days = period_to_days(period)
    start_date = Date.add(Date.utc_today(), -days)

    daily_data =
      DailyUsage
      |> where([d], d.organization_id == ^org_id and d.date >= ^start_date)
      |> order_by([d], d.date)
      |> Repo.all()

    {start_date, daily_data}
  end

  defp build_usage_result(daily_data, start_date) do
    %{
      api_invocations_series: build_daily_series(daily_data, start_date, :api_invocations),
      api_invocations_total: sum_field(daily_data, :api_invocations),
      generations_series: build_daily_series(daily_data, start_date, :llm_generations),
      llm_generations_total: sum_field(daily_data, :llm_generations),
      tokens_in_series: build_daily_series(daily_data, start_date, :tokens_input),
      tokens_out_series: build_daily_series(daily_data, start_date, :tokens_output),
      tokens_in_total: sum_field(daily_data, :tokens_input),
      tokens_out_total: sum_field(daily_data, :tokens_output),
      cost_series:
        build_daily_series(daily_data, start_date, :llm_cost_cents)
        |> Enum.map(fn %{label: l, value: v} -> %{label: l, value: v / 100} end),
      cost_total_cents: sum_field(daily_data, :llm_cost_cents)
    }
  end

  defp sum_field(data, field), do: data |> Enum.map(&(Map.get(&1, field) || 0)) |> Enum.sum()

  defp period_to_days("24h"), do: 1
  defp period_to_days("7d"), do: 7
  defp period_to_days("30d"), do: 30
  defp period_to_days(_), do: 30

  @spec get_api_extended_metrics(Ecto.UUID.t(), String.t()) :: map()
  def get_api_extended_metrics(org_id, period \\ "24h") do
    {start_date, _group_by} = period_config(period)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    payload_stats = query_payload_stats(org_id, start_dt)

    %{
      unique_consumers: query_unique_consumers(org_id, start_date),
      status_distribution: query_status_distribution(org_id, start_dt),
      avg_request_size: normalize_latency(payload_stats.avg_request_size),
      avg_response_size: normalize_latency(payload_stats.avg_response_size),
      api_key_usage: query_api_key_usage(org_id, start_dt)
    }
  end

  defp query_unique_consumers(org_id, start_date) do
    MetricRollup
    |> join(:inner, [r], a in Api, on: r.api_id == a.id)
    |> where([r, a], a.organization_id == ^org_id and r.date >= ^start_date)
    |> select([r], sum(r.unique_consumers))
    |> Repo.one() || 0
  end

  defp query_status_distribution(org_id, start_dt) do
    InvocationLog
    |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
    |> where([l], l.inserted_at >= ^start_dt)
    |> select([l], %{
      s2xx: filter(count(l.id), l.status_code >= 200 and l.status_code < 300),
      s3xx: filter(count(l.id), l.status_code >= 300 and l.status_code < 400),
      s4xx: filter(count(l.id), l.status_code >= 400 and l.status_code < 500),
      s5xx: filter(count(l.id), l.status_code >= 500)
    })
    |> Repo.one()
  end

  defp query_payload_stats(org_id, start_dt) do
    InvocationLog
    |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
    |> where([l], l.inserted_at >= ^start_dt)
    |> select([l], %{
      avg_request_size: avg(l.request_body_size),
      avg_response_size: avg(l.response_body_size)
    })
    |> Repo.one()
  end

  defp query_api_key_usage(org_id, start_dt) do
    InvocationLog
    |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
    |> join(:left, [l], k in ApiKey, on: l.api_key_id == k.id)
    |> where([l], l.inserted_at >= ^start_dt)
    |> group_by([l, _a, k], [l.api_key_id, k.label, k.key_prefix])
    |> select([l, _a, k], %{
      key_label: k.label,
      key_prefix: k.key_prefix,
      calls: count(l.id),
      errors: filter(count(l.id), l.status_code >= 400),
      avg_latency: avg(l.duration_ms)
    })
    |> order_by([l], desc: count(l.id))
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        key_label: row.key_label || "No key",
        key_prefix: row.key_prefix || "-",
        calls: row.calls,
        errors: row.errors,
        avg_latency: normalize_latency(row.avg_latency)
      }
    end)
  end

  @spec get_flow_extended_metrics(Ecto.UUID.t(), String.t()) :: map()
  def get_flow_extended_metrics(org_id, period \\ "24h") do
    {start_date, _group_by} = period_config(period)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    status_dist =
      FlowExecution
      |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^start_dt)
      |> select([e], %{
        pending: filter(count(e.id), e.status == "pending"),
        running: filter(count(e.id), e.status == "running"),
        completed: filter(count(e.id), e.status == "completed"),
        failed: filter(count(e.id), e.status == "failed"),
        halted: filter(count(e.id), e.status == "halted")
      })
      |> Repo.one()

    longest_executions =
      FlowExecution
      |> join(:inner, [e], f in Flow, on: e.flow_id == f.id)
      |> where(
        [e],
        e.organization_id == ^org_id and e.inserted_at >= ^start_dt and not is_nil(e.duration_ms)
      )
      |> order_by([e], desc: e.duration_ms)
      |> limit(5)
      |> select([e, f], %{
        flow_name: f.name,
        status: e.status,
        duration_ms: e.duration_ms,
        started_at: e.started_at
      })
      |> Repo.all()

    recent_failures =
      FlowExecution
      |> join(:inner, [e], f in Flow, on: e.flow_id == f.id)
      |> where(
        [e],
        e.organization_id == ^org_id and e.status == "failed" and e.inserted_at >= ^start_dt
      )
      |> order_by([e], desc: e.inserted_at)
      |> limit(5)
      |> select([e, f], %{
        flow_name: f.name,
        error: e.error,
        finished_at: e.finished_at
      })
      |> Repo.all()

    %{
      status_distribution: status_dist,
      longest_executions: longest_executions,
      recent_failures: recent_failures
    }
  end

  @spec get_llm_metrics(Ecto.UUID.t(), String.t()) :: map()
  def get_llm_metrics(org_id, period \\ "30d") do
    days = period_to_days(period)
    start_dt = DateTime.add(DateTime.utc_now(), -days * 86_400)
    start_date = Date.add(Date.utc_today(), -days)
    totals = query_llm_totals(org_id, start_dt)

    daily_series = query_llm_daily(org_id, start_dt)

    %{
      total_calls: totals.total_calls || 0,
      total_input_tokens: totals.total_input_tokens || 0,
      total_output_tokens: totals.total_output_tokens || 0,
      total_cost_cents: totals.total_cost_cents || 0,
      avg_duration_ms: normalize_latency(totals.avg_duration_ms),
      by_model: query_llm_by_model(org_id, start_dt),
      by_operation: query_llm_by_operation(org_id, start_dt),
      cost_by_api: query_llm_cost_by_api(org_id, start_dt),
      conversations: query_conversation_stats(org_id),
      runs: query_run_stats(org_id, start_dt),
      calls_series: build_llm_daily_series(daily_series, start_date, :calls),
      cost_series: build_llm_daily_series(daily_series, start_date, :cost_cents),
      tokens_series: build_llm_daily_series(daily_series, start_date, :input_tokens),
      duration_series: build_llm_daily_series(daily_series, start_date, :avg_duration)
    }
  end

  defp query_llm_totals(org_id, start_dt) do
    LlmUsage
    |> where([u], u.organization_id == ^org_id and u.inserted_at >= ^start_dt)
    |> select([u], %{
      total_calls: count(u.id),
      total_input_tokens: sum(u.input_tokens),
      total_output_tokens: sum(u.output_tokens),
      total_cost_cents: sum(u.cost_cents),
      avg_duration_ms: avg(u.duration_ms)
    })
    |> Repo.one()
  end

  defp query_llm_by_model(org_id, start_dt) do
    LlmUsage
    |> where([u], u.organization_id == ^org_id and u.inserted_at >= ^start_dt)
    |> group_by([u], [u.provider, u.model])
    |> select([u], %{
      provider: u.provider,
      model: u.model,
      calls: count(u.id),
      input_tokens: sum(u.input_tokens),
      output_tokens: sum(u.output_tokens),
      cost_cents: sum(u.cost_cents),
      avg_duration_ms: avg(u.duration_ms)
    })
    |> order_by([u], desc: count(u.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | avg_duration_ms: normalize_latency(row.avg_duration_ms)}
    end)
  end

  defp query_llm_by_operation(org_id, start_dt) do
    LlmUsage
    |> where([u], u.organization_id == ^org_id and u.inserted_at >= ^start_dt)
    |> group_by([u], u.operation)
    |> select([u], %{
      operation: u.operation,
      calls: count(u.id),
      cost_cents: sum(u.cost_cents),
      avg_duration_ms: avg(u.duration_ms)
    })
    |> order_by([u], desc: count(u.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | avg_duration_ms: normalize_latency(row.avg_duration_ms)}
    end)
  end

  defp query_llm_cost_by_api(org_id, start_dt) do
    LlmUsage
    |> join(:left, [u], a in Api, on: u.api_id == a.id)
    |> where([u], u.organization_id == ^org_id and u.inserted_at >= ^start_dt)
    |> group_by([u, a], [a.id, a.name])
    |> select([u, a], %{
      api_name: a.name,
      calls: count(u.id),
      cost_cents: sum(u.cost_cents),
      input_tokens: sum(u.input_tokens),
      output_tokens: sum(u.output_tokens)
    })
    |> order_by([u], desc: sum(u.cost_cents))
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | api_name: row.api_name || "System"}
    end)
  end

  defp query_conversation_stats(org_id) do
    Conversation
    |> where([c], c.organization_id == ^org_id)
    |> select([c], %{
      total: count(c.id),
      active: filter(count(c.id), c.status == "active"),
      total_tokens: sum(c.total_input_tokens) + sum(c.total_output_tokens),
      total_cost_cents: sum(c.total_cost_cents)
    })
    |> Repo.one()
  end

  defp query_run_stats(org_id, start_dt) do
    Run
    |> where([r], r.organization_id == ^org_id and r.inserted_at >= ^start_dt)
    |> select([r], %{
      total: count(r.id),
      completed: filter(count(r.id), r.status == "completed"),
      failed: filter(count(r.id), r.status == "failed"),
      avg_iterations: avg(r.iteration_count),
      avg_duration_ms: avg(r.duration_ms)
    })
    |> Repo.one()
  end

  defp query_llm_daily(org_id, start_dt) do
    LlmUsage
    |> where([u], u.organization_id == ^org_id and u.inserted_at >= ^start_dt)
    |> group_by([u], fragment("?::date", u.inserted_at))
    |> order_by([u], fragment("?::date", u.inserted_at))
    |> select([u], %{
      date: fragment("?::date", u.inserted_at),
      calls: count(u.id),
      cost_cents: sum(u.cost_cents),
      input_tokens: sum(u.input_tokens),
      output_tokens: sum(u.output_tokens),
      avg_duration: avg(u.duration_ms)
    })
    |> Repo.all()
  end

  # -- Flow series helpers --

  defp flow_series_data(org_id, start_dt, :hourly) do
    FlowExecution
    |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^start_dt)
    |> group_by([e], fragment("EXTRACT(HOUR FROM ?)::integer", e.inserted_at))
    |> order_by([e], fragment("EXTRACT(HOUR FROM ?)::integer", e.inserted_at))
    |> select([e], %{
      bucket: fragment("EXTRACT(HOUR FROM ?)::integer", e.inserted_at),
      executions: count(e.id),
      failures: filter(count(e.id), e.status == "failed"),
      avg_duration: avg(e.duration_ms)
    })
    |> Repo.all()
  end

  defp flow_series_data(org_id, start_dt, :daily) do
    FlowExecution
    |> where([e], e.organization_id == ^org_id and e.inserted_at >= ^start_dt)
    |> group_by([e], fragment("?::date", e.inserted_at))
    |> order_by([e], fragment("?::date", e.inserted_at))
    |> select([e], %{
      bucket: fragment("?::date", e.inserted_at),
      executions: count(e.id),
      failures: filter(count(e.id), e.status == "failed"),
      avg_duration: avg(e.duration_ms)
    })
    |> Repo.all()
  end

  defp build_flow_series(data, _start_date, :hourly, field) do
    lookup = Map.new(data, fn r -> {r.bucket, safe_number(Map.get(r, field))} end)

    Enum.map(0..23, fn hour ->
      %{
        label: hour |> Integer.to_string() |> String.pad_leading(2, "0"),
        value: Map.get(lookup, hour, 0)
      }
    end)
  end

  defp build_flow_series(data, start_date, :daily, field) do
    today = Date.utc_today()
    lookup = Map.new(data, fn r -> {r.bucket, safe_number(Map.get(r, field))} end)

    Date.range(start_date, today)
    |> Enum.map(fn date ->
      %{
        label: Calendar.strftime(date, "%b %d"),
        value: Map.get(lookup, date, 0)
      }
    end)
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

  defp build_llm_daily_series(data, start_date, field) do
    today = Date.utc_today()
    lookup = Map.new(data, fn r -> {r.date, safe_number(Map.get(r, field))} end)

    Date.range(start_date, today)
    |> Enum.map(fn date ->
      %{
        label: Calendar.strftime(date, "%b %d"),
        value: Map.get(lookup, date, 0)
      }
    end)
  end
end
