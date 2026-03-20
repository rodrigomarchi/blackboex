defmodule BlackboexWeb.Admin.SubscriptionLive do
  @moduledoc """
  Backpex LiveResource for viewing subscriptions in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Billing.Subscription,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Billing.Subscription.admin_changeset/3,
      create_changeset: &Blackboex.Billing.Subscription.admin_changeset/3
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
        module: Backpex.Fields.Text,
        label: "Plan"
      },
      status: %{
        module: Backpex.Fields.Text,
        label: "Status"
      },
      stripe_customer_id: %{
        module: Backpex.Fields.Text,
        label: "Stripe Customer",
        only: [:show]
      },
      current_period_end: %{
        module: Backpex.Fields.DateTime,
        label: "Period End"
      },
      cancel_at_period_end: %{
        module: Backpex.Fields.Boolean,
        label: "Canceling"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, :index, _item), do: platform_admin?(assigns)
  def can?(assigns, :show, _item), do: platform_admin?(assigns)
  def can?(_assigns, _action, _item), do: false

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
