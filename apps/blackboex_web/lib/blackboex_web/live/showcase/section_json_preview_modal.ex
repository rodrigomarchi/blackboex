defmodule BlackboexWeb.Showcase.Sections.JsonPreviewModal do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.CodeViewer

  @mock_json ~S"""
  {
    "id": "flow-1",
    "name": "User Onboarding Flow",
    "slug": "user-onboarding",
    "status": "active",
    "nodes": [
      {"id": "node-1", "type": "trigger", "config": {"event": "user.created"}},
      {"id": "node-2", "type": "action", "config": {"handler": "send_welcome_email"}},
      {"id": "node-3", "type": "condition", "config": {"field": "user.plan", "op": "eq", "value": "pro"}}
    ],
    "edges": [
      {"from": "node-1", "to": "node-2"},
      {"from": "node-2", "to": "node-3"}
    ]
  }
  """

  @code_static ~S"""
  <%!-- Rendered when show_json_preview is true in the LiveView --%>
  <.json_preview_modal
    :if={@show_json_preview}
    flow={@flow}
    json_preview={@json_preview}
  />
  """

  @code_usage ~S"""
  <%!-- LiveView handle_event to open the modal --%>
  def handle_event("request_json_preview", _params, socket) do
    json = Jason.encode!(socket.assigns.flow_definition, pretty: true)
    {:noreply, assign(socket, show_json_preview: true, json_preview: json)}
  end

  def handle_event("close_json_modal", _params, socket) do
    {:noreply, assign(socket, show_json_preview: false)}
  end
  """

  @flow %{name: "User Onboarding Flow", slug: "user-onboarding", status: "active", id: "flow-1"}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_static, @code_static)
      |> assign(:code_usage, @code_usage)
      |> assign(:mock_json, @mock_json)
      |> assign(:flow, @flow)

    ~H"""
    <.section_header
      title="JsonPreviewModal"
      description="Modal for previewing the JSON representation of a flow definition. Used in the flow editor to inspect the underlying flow structure."
      module="BlackboexWeb.Components.FlowEditor.JsonPreviewModal"
    />
    <div class="space-y-10">
      <.showcase_block title="Static preview — rendered inline (without overlay)" code={@code_static}>
        <div class="flex flex-col w-full h-[400px] rounded-xl border bg-card shadow-2xl overflow-hidden">
          <div class="flex items-center justify-between border-b px-5 py-3">
            <div class="flex items-center gap-2">
              <.icon name="hero-code-bracket" class="size-5 text-accent-violet" />
              <span class="font-semibold text-sm">Flow Definition (JSON)</span>
            </div>
            <div class="flex items-center gap-1.5">
              <.button variant="outline" size="sm">
                <.icon name="hero-clipboard-document" class="mr-1.5 size-4 text-accent-sky" /> Copy
              </.button>
              <.button variant="outline" size="sm">
                <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-accent-emerald" /> Download
              </.button>
              <.button variant="ghost-muted" size="icon-sm">
                <.icon name="hero-x-mark" class="size-5" />
              </.button>
            </div>
          </div>
          <div class="flex-1 overflow-auto p-5">
            <div class="h-full rounded-lg overflow-hidden border">
              <.code_viewer code={@mock_json} label="JSON" />
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Usage pattern — triggering from LiveView" code={@code_usage}>
        <div class="rounded-lg bg-muted/50 p-4 text-sm text-muted-foreground">
          The modal is conditionally rendered via <code class="font-mono text-xs bg-muted px-1 rounded">:if={@show_json_preview}</code>.
          Trigger it with <code class="font-mono text-xs bg-muted px-1 rounded">phx-click="request_json_preview"</code>
          in the flow header. See the full usage example in the code block above.
        </div>
      </.showcase_block>
    </div>
    """
  end

end
