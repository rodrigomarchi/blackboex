defmodule BlackboexWeb.Admin.ProcessedEventLive do
  @moduledoc """
  Backpex LiveResource for viewing processed Stripe events in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Billing.ProcessedEvent,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Billing.ProcessedEvent.admin_changeset/3,
      create_changeset: &Blackboex.Billing.ProcessedEvent.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Processed Event"

  @impl Backpex.LiveResource
  def plural_name, do: "Processed Events"

  @impl Backpex.LiveResource
  def fields do
    [
      event_id: %{
        module: Backpex.Fields.Text,
        label: "Event ID",
        searchable: true
      },
      event_type: %{
        module: Backpex.Fields.Text,
        label: "Event Type",
        searchable: true
      },
      processed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Processed At"
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
