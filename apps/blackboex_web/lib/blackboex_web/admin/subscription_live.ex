defmodule BlackboexWeb.Admin.SubscriptionLive do
  @moduledoc """
  Backpex LiveResource for viewing subscriptions in the admin panel.
  Read-only.
  """

  alias Blackboex.Billing.Subscription

  use Backpex.LiveResource,
    adapter_config: [
      schema: Subscription,
      repo: Blackboex.Repo,
      update_changeset: &Subscription.admin_changeset/3,
      create_changeset: &Subscription.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Subscription"

  @impl Backpex.LiveResource
  def plural_name, do: "Subscriptions"

  @impl Backpex.LiveResource
  def fields do
    [
      plan: %{
        module: Backpex.Fields.Select,
        label: "Plan",
        options: [Free: "free", Pro: "pro", Enterprise: "enterprise"]
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        options: [
          Active: "active",
          "Past Due": "past_due",
          Canceled: "canceled",
          Trialing: "trialing"
        ]
      },
      stripe_customer_id: %{
        module: Backpex.Fields.Text,
        label: "Stripe Customer"
      },
      stripe_subscription_id: %{
        module: Backpex.Fields.Text,
        label: "Stripe Subscription"
      },
      current_period_start: %{
        module: Backpex.Fields.DateTime,
        label: "Period Start"
      },
      current_period_end: %{
        module: Backpex.Fields.DateTime,
        label: "Period End"
      },
      cancel_at_period_end: %{
        module: Backpex.Fields.Boolean,
        label: "Canceling"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
