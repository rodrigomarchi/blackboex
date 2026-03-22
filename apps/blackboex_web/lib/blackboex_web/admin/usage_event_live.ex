defmodule BlackboexWeb.Admin.UsageEventLive do
  @moduledoc """
  Backpex LiveResource for viewing usage events in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Billing.UsageEvent,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Billing.UsageEvent.admin_changeset/3,
      create_changeset: &Blackboex.Billing.UsageEvent.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Usage Event"

  @impl Backpex.LiveResource
  def plural_name, do: "Usage Events"

  @impl Backpex.LiveResource
  def fields do
    [
      event_type: %{
        module: Backpex.Fields.Text,
        label: "Event Type",
        searchable: true
      },
      metadata: %{
        module: Backpex.Fields.Textarea,
        label: "Metadata",
        readonly: true,
        only: [:show]
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID",
        readonly: true,
        only: [:show]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "When"
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
