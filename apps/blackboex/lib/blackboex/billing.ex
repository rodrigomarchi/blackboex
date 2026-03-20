defmodule Blackboex.Billing do
  @moduledoc """
  The Billing context. Manages subscriptions, checkout sessions,
  and usage tracking for plan-based billing.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Audit
  alias Blackboex.Billing.{DailyUsage, StripeClient, Subscription, UsageEvent}
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo
  alias Ecto.Multi

  require Logger

  # Stripe price IDs — configured per environment
  @price_ids %{
    "pro" => "price_pro_monthly",
    "enterprise" => "price_enterprise_monthly"
  }

  @spec get_subscription(integer() | binary()) :: Subscription.t() | nil
  def get_subscription(organization_id) do
    Repo.get_by(Subscription, organization_id: organization_id)
  end

  @spec create_checkout_session(Organization.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{url: String.t()}} | {:error, term()}
  def create_checkout_session(%Organization{} = org, plan, success_url, cancel_url)
      when plan in ~w(pro enterprise) do
    price_id = Map.fetch!(@price_ids, plan)

    params = %{
      customer_email: nil,
      price_id: price_id,
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: %{"organization_id" => org.id, "plan" => plan}
    }

    case StripeClient.client().create_checkout_session(params) do
      {:ok, session} -> {:ok, %{url: session.url}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_portal_session(Organization.t(), String.t()) ::
          {:ok, %{url: String.t()}} | {:error, term()}
  def create_portal_session(%Organization{} = org, return_url) do
    case get_subscription(org.id) do
      %Subscription{stripe_customer_id: cid} when is_binary(cid) ->
        case StripeClient.client().create_portal_session(cid, return_url) do
          {:ok, session} -> {:ok, %{url: session.url}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :no_subscription}
    end
  end

  @spec create_or_update_subscription(map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_subscription(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]

    Multi.new()
    |> Multi.run(:subscription, fn _repo, _changes ->
      case get_subscription(org_id) do
        nil ->
          %Subscription{}
          |> Subscription.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> Subscription.changeset(attrs)
          |> Repo.update()
      end
    end)
    |> Multi.run(:sync_org_plan, fn _repo, %{subscription: sub} ->
      org = Repo.get!(Organization, org_id)
      plan_atom = plan_string_to_atom(sub.plan)

      org
      |> Ecto.Changeset.change(plan: plan_atom)
      |> Repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{subscription: sub}} ->
        Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
          Audit.log("subscription.updated", %{
            resource_type: "subscription",
            resource_id: sub.id,
            organization_id: org_id
          })
        end)

        {:ok, sub}

      {:error, :subscription, changeset, _} ->
        {:error, changeset}

      {:error, :sync_org_plan, changeset, _} ->
        {:error, changeset}
    end
  end

  @spec sync_subscription(Organization.t()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def sync_subscription(%Organization{} = org) do
    case get_subscription(org.id) do
      %Subscription{stripe_subscription_id: sid} when is_binary(sid) ->
        case StripeClient.client().retrieve_subscription(sid) do
          {:ok, stripe_sub} ->
            create_or_update_subscription(%{
              organization_id: org.id,
              plan: stripe_sub_to_plan(stripe_sub),
              status: to_string(stripe_sub.status),
              current_period_start: DateTime.from_unix!(stripe_sub.current_period_start),
              current_period_end: DateTime.from_unix!(stripe_sub.current_period_end),
              cancel_at_period_end: stripe_sub.cancel_at_period_end || false
            })

          {:error, reason} ->
            Logger.warning("Failed to sync subscription: #{inspect(reason)}")
            {:error, reason}
        end

      _ ->
        {:error, :no_subscription}
    end
  end

  defp stripe_sub_to_plan(%{items: %{data: [%{price: %{id: price_id}} | _]}}) do
    @price_ids
    |> Enum.find(fn {_plan, pid} -> pid == price_id end)
    |> case do
      {plan, _} -> plan
      nil -> "free"
    end
  end

  defp stripe_sub_to_plan(_), do: "free"

  @plan_atom_map %{"free" => :free, "pro" => :pro, "enterprise" => :enterprise}

  defp plan_string_to_atom(plan) when is_binary(plan) do
    Map.get(@plan_atom_map, plan, :free)
  end

  # --- Usage Tracking ---

  @spec record_usage_event(map()) :: {:ok, UsageEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_usage_event(attrs) do
    %UsageEvent{}
    |> UsageEvent.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_daily_usage(binary(), Date.t()) :: DailyUsage.t() | nil
  def get_daily_usage(organization_id, date) do
    Repo.get_by(DailyUsage, organization_id: organization_id, date: date)
  end

  @spec get_daily_usage_for_period(binary(), Date.t(), Date.t()) :: [DailyUsage.t()]
  def get_daily_usage_for_period(organization_id, start_date, end_date) do
    DailyUsage
    |> where([d], d.organization_id == ^organization_id)
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> order_by([d], asc: d.date)
    |> Repo.all()
  end

  @spec count_usage_events_today(binary(), String.t()) :: non_neg_integer()
  def count_usage_events_today(organization_id, event_type) do
    today_start = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

    UsageEvent
    |> where([e], e.organization_id == ^organization_id)
    |> where([e], e.event_type == ^event_type)
    |> where([e], e.inserted_at >= ^today_start)
    |> Repo.aggregate(:count)
  end

  @spec sum_monthly_usage(binary(), String.t()) :: non_neg_integer()
  def sum_monthly_usage(organization_id, event_type) do
    today = Date.utc_today()
    month_start = Date.beginning_of_month(today)
    yesterday = Date.add(today, -1)

    # Sum from aggregated daily_usage for completed days
    field_name =
      case event_type do
        "api_invocation" -> :api_invocations
        "llm_generation" -> :llm_generations
      end

    aggregated =
      DailyUsage
      |> where([d], d.organization_id == ^organization_id)
      |> where([d], d.date >= ^month_start and d.date <= ^yesterday)
      |> Repo.aggregate(:sum, field_name) || 0

    # Add today's live count
    today_count = count_usage_events_today(organization_id, event_type)

    aggregated + today_count
  end
end
