defmodule Blackboex.Billing.BillingQueries do
  @moduledoc "Composable query builders for Billing schemas."
  import Ecto.Query, warn: false
  alias Blackboex.Billing.{DailyUsage, UsageEvent}

  @spec daily_usage_for_period(binary(), Date.t(), Date.t()) :: Ecto.Query.t()
  def daily_usage_for_period(organization_id, start_date, end_date) do
    DailyUsage
    |> where([d], d.organization_id == ^organization_id)
    |> where([d], is_nil(d.project_id))
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> order_by([d], asc: d.date)
  end

  @spec usage_events_today(binary(), String.t(), NaiveDateTime.t()) :: Ecto.Query.t()
  def usage_events_today(organization_id, event_type, today_start) do
    UsageEvent
    |> where([e], e.organization_id == ^organization_id)
    |> where([e], e.event_type == ^event_type)
    |> where([e], e.inserted_at >= ^today_start)
  end

  @spec monthly_daily_usage(binary(), Date.t(), Date.t()) :: Ecto.Query.t()
  def monthly_daily_usage(organization_id, month_start, end_date) do
    DailyUsage
    |> where([d], d.organization_id == ^organization_id)
    |> where([d], is_nil(d.project_id))
    |> where([d], d.date >= ^month_start and d.date <= ^end_date)
  end

  @spec org_usage_summary(binary(), Date.t()) :: Ecto.Query.t()
  def org_usage_summary(organization_id, since_date) do
    DailyUsage
    |> where([d], d.organization_id == ^organization_id)
    |> where([d], is_nil(d.project_id))
    |> where([d], d.date >= ^since_date)
  end

  @spec project_usage_summary(binary(), Date.t()) :: Ecto.Query.t()
  def project_usage_summary(project_id, since_date) do
    DailyUsage
    |> where([d], d.project_id == ^project_id)
    |> where([d], d.date >= ^since_date)
  end
end
