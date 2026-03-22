defmodule BlackboexWeb.Admin.InvocationLogLive do
  @moduledoc """
  Backpex LiveResource for viewing API invocation logs in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.InvocationLog,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.InvocationLog.admin_changeset/3,
      create_changeset: &Blackboex.Apis.InvocationLog.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Invocation Log"

  @impl Backpex.LiveResource
  def plural_name, do: "Invocation Logs"

  @impl Backpex.LiveResource
  def fields do
    [
      method: %{
        module: Backpex.Fields.Text,
        label: "Method",
        searchable: true
      },
      path: %{
        module: Backpex.Fields.Text,
        label: "Path",
        searchable: true
      },
      status_code: %{
        module: Backpex.Fields.Number,
        label: "Status"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      request_body_size: %{
        module: Backpex.Fields.Number,
        label: "Request Size",
        only: [:show]
      },
      response_body_size: %{
        module: Backpex.Fields.Number,
        label: "Response Size",
        only: [:show]
      },
      ip_address: %{
        module: Backpex.Fields.Text,
        label: "IP Address",
        searchable: true,
        only: [:show]
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true,
        only: [:show]
      },
      api_key_id: %{
        module: Backpex.Fields.Text,
        label: "API Key ID",
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
