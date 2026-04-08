defmodule BlackboexWeb.FlowLive.Edit do
  @moduledoc """
  Full-screen flow editor with Drawflow canvas.
  Mounts the Drawflow JS library via phx-hook and communicates
  graph state as JSON over the LiveView socket.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Flows
  alias Blackboex.Policy

  @node_types [
    %{
      type: "start",
      label: "Start",
      subtitle: "Trigger",
      icon: "hero-play",
      color: "#10b981",
      inputs: 0,
      outputs: 1
    },
    %{
      type: "http_request",
      label: "HTTP Request",
      subtitle: "GET / POST / PUT",
      icon: "hero-globe-alt",
      color: "#8b5cf6",
      inputs: 1,
      outputs: 1
    },
    %{
      type: "transform",
      label: "Transform",
      subtitle: "Map & filter data",
      icon: "hero-code-bracket",
      color: "#f59e0b",
      inputs: 1,
      outputs: 1
    },
    %{
      type: "condition",
      label: "Condition",
      subtitle: "If / else branch",
      icon: "hero-arrow-path-rounded-square",
      color: "#3b82f6",
      inputs: 1,
      outputs: 2
    },
    %{
      type: "response",
      label: "Response",
      subtitle: "Return result",
      icon: "hero-arrow-right-start-on-rectangle",
      color: "#ef4444",
      inputs: 1,
      outputs: 0
    },
    %{
      type: "end",
      label: "End",
      subtitle: "Stop flow",
      icon: "hero-stop",
      color: "#6b7280",
      inputs: 1,
      outputs: 0
    }
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    case org && Flows.get_flow(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Flow not found.")
         |> push_navigate(to: ~p"/flows")}

      flow ->
        {:ok,
         assign(socket,
           flow: flow,
           page_title: flow.name,
           node_types: @node_types,
           saving: false,
           saved: false
         )}
    end
  end

  @impl true
  def handle_event("save_definition", %{"definition" => definition}, socket) do
    flow = socket.assigns.flow
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:flow_update, scope, org) do
      case Flows.update_definition(flow, definition) do
        {:ok, updated_flow} ->
          {:noreply,
           socket
           |> assign(flow: updated_flow, saving: false, saved: true)
           |> push_event("definition_saved", %{})}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> assign(saving: false)
           |> put_flash(:error, "Could not save flow.")}
      end
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  @impl true
  def handle_event("request_save", _params, socket) do
    {:noreply,
     socket
     |> assign(saving: true, saved: false)
     |> push_event("export_definition", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col overflow-hidden bg-background text-foreground">
      <%!-- Top bar --%>
      <header class="flex h-12 shrink-0 items-center justify-between border-b bg-card px-4">
        <div class="flex items-center gap-3">
          <.link navigate={~p"/flows"} class="text-muted-foreground hover:text-foreground">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-sm font-semibold truncate max-w-xs">{@flow.name}</h1>
          <span class="rounded bg-muted px-2 py-0.5 text-xs text-muted-foreground">
            {@flow.status}
          </span>
        </div>

        <div class="flex items-center gap-2">
          <span :if={@saved} class="text-xs text-green-600 dark:text-green-400">Saved</span>
          <.button
            variant="primary"
            size="sm"
            phx-click="request_save"
            disabled={@saving}
          >
            <%= if @saving do %>
              <.icon name="hero-arrow-path" class="mr-1.5 size-4 animate-spin" /> Saving...
            <% else %>
              <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4" /> Save
            <% end %>
          </.button>
        </div>
      </header>

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <%!-- Node palette sidebar --%>
        <aside class="flex w-56 shrink-0 flex-col border-r bg-card">
          <div class="border-b px-3 py-2">
            <h2 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Nodes
            </h2>
          </div>
          <div class="flex-1 overflow-y-auto p-2 space-y-1.5">
            <div
              :for={node <- @node_types}
              draggable="true"
              data-node-type={node.type}
              data-node-label={node.label}
              data-node-inputs={node.inputs}
              data-node-outputs={node.outputs}
              class="flex cursor-grab items-center gap-2.5 rounded-lg border bg-background p-2.5 hover:border-primary/50 hover:shadow-sm active:cursor-grabbing transition-all"
            >
              <div
                class="flex size-8 shrink-0 items-center justify-center rounded-lg"
                style={"background: #{node.color}15; color: #{node.color}"}
              >
                <.icon name={node.icon} class="size-4" />
              </div>
              <div class="min-w-0">
                <div class="text-sm font-medium leading-tight">{node.label}</div>
                <div class="text-xs text-muted-foreground leading-tight">{node.subtitle}</div>
              </div>
            </div>
          </div>
        </aside>

        <%!-- Drawflow canvas --%>
        <div class="flex-1 relative">
          <div
            id="drawflow-canvas"
            phx-hook="DrawflowEditor"
            phx-update="ignore"
            data-definition={Jason.encode!(@flow.definition)}
            class="h-full w-full"
          />
        </div>
      </div>
    </div>
    """
  end
end
