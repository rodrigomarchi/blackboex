defmodule BlackboexWeb.Admin.InvocationLogLive do
  @moduledoc """
  Backpex LiveResource for viewing API invocation logs in the admin panel.
  Read-only.
  """

  alias Blackboex.Apis.InvocationLog

  use Backpex.LiveResource,
    adapter_config: [
      schema: InvocationLog,
      repo: Blackboex.Repo,
      update_changeset: &InvocationLog.admin_changeset/3,
      create_changeset: &InvocationLog.admin_changeset/3
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
        label: "Request Size"
      },
      response_body_size: %{
        module: Backpex.Fields.Number,
        label: "Response Size"
      },
      ip_address: %{
        module: Backpex.Fields.Text,
        label: "IP Address",
        searchable: true
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      api_key_id: %{
        module: Backpex.Fields.Text,
        label: "API Key ID"
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
