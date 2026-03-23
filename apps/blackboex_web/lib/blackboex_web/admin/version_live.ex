defmodule BlackboexWeb.Admin.VersionLive do
  @moduledoc """
  Backpex LiveResource for viewing ExAudit version records in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Audit.Version,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Audit.Version.admin_changeset/3,
      create_changeset: &Blackboex.Audit.Version.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :recorded_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Version"

  @impl Backpex.LiveResource
  def plural_name, do: "Versions"

  @impl Backpex.LiveResource
  def fields do
    [
      entity_id: %{
        module: Backpex.Fields.Text,
        label: "Entity ID"
      },
      entity_schema: %{
        module: Backpex.Fields.Text,
        label: "Entity Schema",
        searchable: true
      },
      action: %{
        module: Backpex.Fields.Text,
        label: "Action",
        searchable: true
      },
      recorded_at: %{
        module: Backpex.Fields.DateTime,
        label: "Recorded At"
      },
      rollback: %{
        module: Backpex.Fields.Boolean,
        label: "Rollback"
      },
      actor_id: %{
        module: Backpex.Fields.Text,
        label: "Actor ID",
        readonly: true,
        only: [:show]
      },
      ip_address: %{
        module: Backpex.Fields.Text,
        label: "IP Address",
        only: [:show]
      },
      patch: %{
        module: Backpex.Fields.Text,
        label: "Patch",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          patch = assigns.item.patch
          text = if is_map(patch), do: inspect(patch, pretty: true), else: to_string(patch)
          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap"><%= @text %></pre>
          """
        end
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
