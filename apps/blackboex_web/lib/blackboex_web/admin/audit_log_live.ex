defmodule BlackboexWeb.Admin.AuditLogLive do
  @moduledoc """
  Backpex LiveResource for viewing audit logs in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Audit.AuditLog,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Audit.AuditLog.admin_changeset/3,
      create_changeset: &Blackboex.Audit.AuditLog.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Audit Log"

  @impl Backpex.LiveResource
  def plural_name, do: "Audit Logs"

  @impl Backpex.LiveResource
  def fields do
    [
      action: %{
        module: Backpex.Fields.Text,
        label: "Action",
        searchable: true
      },
      resource_type: %{
        module: Backpex.Fields.Text,
        label: "Resource Type"
      },
      resource_id: %{
        module: Backpex.Fields.Text,
        label: "Resource ID"
      },
      metadata: %{
        module: Backpex.Fields.Text,
        label: "Metadata",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :metadata)

          text =
            if is_map(value) and value != %{},
              do: Jason.encode!(value, pretty: true),
              else: "—"

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
          """
        end
      },
      ip_address: %{
        module: Backpex.Fields.Text,
        label: "IP Address"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "When"
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
