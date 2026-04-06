defmodule Blackboex.BillingFixtures do
  @moduledoc """
  Test helpers for creating billing entities.
  """

  alias Blackboex.Billing.{DailyUsage, Subscription, UsageEvent}
  alias Blackboex.Repo

  @doc """
  Creates a subscription for the given organization.

  ## Options

    * `:organization_id` - (required) the org ID
    * `:plan` - subscription plan (default: "pro")
    * `:status` - subscription status (default: "active")
    * `:stripe_subscription_id` - Stripe sub ID (default: auto-generated)
    * `:stripe_customer_id` - Stripe customer ID (default: nil)

  Returns the subscription struct.
  """
  @spec subscription_fixture(map()) :: Subscription.t()
  def subscription_fixture(attrs) do
    %Subscription{}
    |> Subscription.changeset(
      Map.merge(
        %{
          plan: "pro",
          status: "active",
          stripe_subscription_id: "sub_test_#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  Creates a daily usage record for the given organization.

  ## Options

    * `:organization_id` - (required) the org ID
    * `:date` - the date (default: yesterday)
    * Any DailyUsage fields (api_invocations, llm_generations, etc.)

  Returns the daily usage struct.
  """
  @spec daily_usage_fixture(map()) :: DailyUsage.t()
  def daily_usage_fixture(attrs) do
    %DailyUsage{}
    |> DailyUsage.changeset(
      Map.merge(
        %{
          date: Date.add(Date.utc_today(), -1)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  Creates a usage event for the given organization.

  ## Options

    * `:organization_id` - (required) the org ID
    * `:event_type` - event type (default: "api_invocation")

  Returns the usage event struct.
  """
  @spec usage_event_fixture(map()) :: UsageEvent.t()
  def usage_event_fixture(attrs) do
    %UsageEvent{}
    |> UsageEvent.changeset(
      Map.merge(
        %{
          event_type: "api_invocation"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
