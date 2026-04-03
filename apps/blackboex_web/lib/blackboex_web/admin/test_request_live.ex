defmodule BlackboexWeb.Admin.TestRequestLive do
  @moduledoc """
  Backpex LiveResource for viewing test requests in the admin panel.
  Read-only.
  """

  alias Blackboex.Testing.TestRequest

  use Backpex.LiveResource,
    adapter_config: [
      schema: TestRequest,
      repo: Blackboex.Repo,
      update_changeset: &TestRequest.admin_changeset/3,
      create_changeset: &TestRequest.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Test Request"

  @impl Backpex.LiveResource
  def plural_name, do: "Test Requests"

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
      response_status: %{
        module: Backpex.Fields.Number,
        label: "Status"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      headers: %{
        module: Backpex.Fields.Text,
        label: "Request Headers",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :headers)

          text =
            if is_map(value) or is_list(value),
              do: inspect(value, pretty: true, limit: :infinity),
              else: to_string(value || "")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
          """
        end
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Request Body"
      },
      response_headers: %{
        module: Backpex.Fields.Text,
        label: "Response Headers",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :response_headers)

          text =
            if is_map(value) or is_list(value),
              do: inspect(value, pretty: true, limit: :infinity),
              else: to_string(value || "")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
          """
        end
      },
      response_body: %{
        module: Backpex.Fields.Textarea,
        label: "Response Body"
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
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
