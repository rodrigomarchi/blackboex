defmodule Blackboex.Billing.UsageAggregationWorker do
  @moduledoc """
  Oban worker that aggregates UsageEvents into DailyUsage records.
  Runs daily to aggregate the previous day's usage.
  Idempotent — re-running replaces existing daily_usage records.
  """

  use Oban.Worker, queue: :billing, max_attempts: 3

  import Ecto.Query, warn: false

  alias Blackboex.Billing.{DailyUsage, UsageEvent}
  alias Blackboex.Repo

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: args}) do
    date =
      case args do
        %{"date" => date_str} -> Date.from_iso8601!(date_str)
        _ -> Date.add(Date.utc_today(), -1)
      end

    aggregate_for_date(date)
  end

  @spec aggregate_for_date(Date.t()) :: :ok
  def aggregate_for_date(date) do
    day_start = NaiveDateTime.new!(date, ~T[00:00:00])
    day_end = NaiveDateTime.new!(Date.add(date, 1), ~T[00:00:00])

    base_query = where(UsageEvent, [e], e.inserted_at >= ^day_start and e.inserted_at < ^day_end)

    # 1. Project-level aggregation — one record per (org, project) per day
    base_query
    |> group_by([e], [e.organization_id, e.project_id])
    |> select([e], %{
      organization_id: e.organization_id,
      project_id: e.project_id,
      api_invocations: count(fragment("CASE WHEN ? = 'api_invocation' THEN 1 END", e.event_type)),
      llm_generations: count(fragment("CASE WHEN ? = 'llm_generation' THEN 1 END", e.event_type)),
      tokens_input:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'tokens_input')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        ),
      tokens_output:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'tokens_output')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        ),
      llm_cost_cents:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'cost_cents')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        )
    })
    |> Repo.all()
    |> Enum.each(fn agg -> upsert_daily_usage(agg, date) end)

    # 2. Org-level aggregation — one record per org per day with project_id: nil
    base_query
    |> group_by([e], [e.organization_id])
    |> select([e], %{
      organization_id: e.organization_id,
      project_id: nil,
      api_invocations: count(fragment("CASE WHEN ? = 'api_invocation' THEN 1 END", e.event_type)),
      llm_generations: count(fragment("CASE WHEN ? = 'llm_generation' THEN 1 END", e.event_type)),
      tokens_input:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'tokens_input')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        ),
      tokens_output:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'tokens_output')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        ),
      llm_cost_cents:
        fragment(
          "COALESCE(SUM(CASE WHEN ? = 'llm_generation' THEN (? ->> 'cost_cents')::int ELSE 0 END), 0)",
          e.event_type,
          e.metadata
        )
    })
    |> Repo.all()
    |> Enum.each(fn agg -> upsert_daily_usage(agg, date) end)

    Logger.info("Usage aggregation complete for #{date}")
    :ok
  end

  defp upsert_daily_usage(%{project_id: nil} = agg, date) do
    attrs = %{
      organization_id: agg.organization_id,
      project_id: nil,
      date: date,
      api_invocations: agg.api_invocations,
      llm_generations: agg.llm_generations,
      tokens_input: agg.tokens_input,
      tokens_output: agg.tokens_output,
      llm_cost_cents: agg.llm_cost_cents
    }

    on_conflict_set = [
      api_invocations: agg.api_invocations,
      llm_generations: agg.llm_generations,
      tokens_input: agg.tokens_input,
      tokens_output: agg.tokens_output,
      llm_cost_cents: agg.llm_cost_cents,
      updated_at: NaiveDateTime.utc_now(:second)
    ]

    %DailyUsage{}
    |> DailyUsage.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: on_conflict_set],
      conflict_target: {:unsafe_fragment, "(organization_id, date) WHERE project_id IS NULL"}
    )
  end

  defp upsert_daily_usage(agg, date) do
    attrs = %{
      organization_id: agg.organization_id,
      project_id: agg.project_id,
      date: date,
      api_invocations: agg.api_invocations,
      llm_generations: agg.llm_generations,
      tokens_input: agg.tokens_input,
      tokens_output: agg.tokens_output,
      llm_cost_cents: agg.llm_cost_cents
    }

    %DailyUsage{}
    |> DailyUsage.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          api_invocations: agg.api_invocations,
          llm_generations: agg.llm_generations,
          tokens_input: agg.tokens_input,
          tokens_output: agg.tokens_output,
          llm_cost_cents: agg.llm_cost_cents,
          updated_at: NaiveDateTime.utc_now(:second)
        ]
      ],
      conflict_target: [:organization_id, :project_id, :date]
    )
  end
end
