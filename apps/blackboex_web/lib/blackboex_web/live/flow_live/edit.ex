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
      outputs: 1,
      group: "flow"
    },
    %{
      type: "elixir_code",
      label: "Elixir Code",
      subtitle: "Run Elixir code",
      icon: "hero-code-bracket",
      color: "#8b5cf6",
      inputs: 1,
      outputs: 1,
      group: "logic"
    },
    %{
      type: "condition",
      label: "Condition",
      subtitle: "Dynamic branches",
      icon: "hero-arrows-right-left",
      color: "#3b82f6",
      inputs: 1,
      outputs: 2,
      group: "logic"
    },
    %{
      type: "end",
      label: "End",
      subtitle: "Stop flow",
      icon: "hero-stop",
      color: "#6b7280",
      inputs: 1,
      outputs: 0,
      group: "flow"
    }
  ]

  @node_type_map Map.new(@node_types, fn n -> {n.type, n} end)

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
           saved: false,
           selected_node: nil,
           show_json_modal: false,
           json_preview: ""
         )}
    end
  end

  # ── Save ─────────────────────────────────────────────────────────────────

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

  # ── Node selection ───────────────────────────────────────────────────────

  @impl true
  def handle_event("node_selected", %{"id" => id, "type" => type, "data" => data}, socket) do
    node_meta = Map.get(@node_type_map, type, %{label: type, icon: "hero-cube", color: "#6b7280"})

    {:noreply,
     assign(socket,
       selected_node: %{
         id: id,
         type: type,
         data: data,
         label: node_meta[:label] || type,
         icon: node_meta[:icon] || "hero-cube",
         color: node_meta[:color] || "#6b7280"
       }
     )}
  end

  @impl true
  def handle_event("node_deselected", _params, socket) do
    {:noreply, assign(socket, selected_node: nil)}
  end

  @impl true
  def handle_event("update_node_data", %{"field" => field, "value" => value}, socket) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        updated_data = Map.put(node.data, field, value)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, selected_node: nil)}
  end

  # ── JSON preview ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("request_json_preview", _params, socket) do
    {:noreply, push_event(socket, "export_json_preview", %{})}
  end

  @impl true
  def handle_event("show_json_preview", %{"definition" => definition}, socket) do
    formatted = Jason.encode!(definition, pretty: true)
    {:noreply, assign(socket, show_json_modal: true, json_preview: formatted)}
  end

  @impl true
  def handle_event("close_json_modal", _params, socket) do
    {:noreply, assign(socket, show_json_modal: false)}
  end

  # ── Render ───────────────────────────────────────────────────────────────

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
          <.button variant="outline" size="sm" phx-click="request_json_preview">
            <.icon name="hero-code-bracket" class="mr-1.5 size-4" /> JSON
          </.button>
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
          <div class="flex-1 overflow-y-auto p-2 space-y-3">
            <.node_group
              label="Flow Control"
              nodes={Enum.filter(@node_types, &(&1.group == "flow"))}
            />
            <.node_group label="Logic" nodes={Enum.filter(@node_types, &(&1.group == "logic"))} />
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

        <%!-- Properties drawer --%>
        <.properties_drawer node={@selected_node} />
      </div>

      <%!-- JSON Preview Modal --%>
      <%= if @show_json_modal do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
          phx-click="close_json_modal"
        >
          <div
            class="flex flex-col w-[80vw] h-[80vh] rounded-xl border bg-card shadow-2xl"
            phx-click-away="close_json_modal"
          >
            <div class="flex items-center justify-between border-b px-5 py-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-code-bracket" class="size-5 text-muted-foreground" />
                <h2 class="text-sm font-semibold">Flow Definition (JSON)</h2>
              </div>
              <div class="flex items-center gap-1.5">
                <.button
                  variant="outline"
                  size="sm"
                  phx-click={
                    JS.dispatch("phx:copy_to_clipboard",
                      detail: %{text: @json_preview}
                    )
                  }
                >
                  <.icon name="hero-clipboard-document" class="mr-1.5 size-4" /> Copy
                </.button>
                <.button
                  variant="outline"
                  size="sm"
                  phx-click={
                    JS.dispatch("phx:download_file",
                      detail: %{
                        content: @json_preview,
                        filename: "#{@flow.slug}-definition.json"
                      }
                    )
                  }
                >
                  <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4" /> Download
                </.button>
                <button
                  phx-click="close_json_modal"
                  class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
            </div>
            <div class="flex-1 overflow-auto p-5">
              <pre class="text-xs font-mono leading-relaxed text-foreground whitespace-pre-wrap"><%= @json_preview %></pre>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Properties drawer ────────────────────────────────────────────────────

  attr :node, :map, default: nil

  defp properties_drawer(%{node: nil} = assigns) do
    ~H"""
    """
  end

  defp properties_drawer(assigns) do
    ~H"""
    <aside class="flex w-80 shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200">
      <%!-- Drawer header --%>
      <div class="flex items-center justify-between border-b px-4 py-3">
        <div class="flex items-center gap-2">
          <div
            class="flex size-7 items-center justify-center rounded-lg"
            style={"background: #{@node.color}15; color: #{@node.color}"}
          >
            <.icon name={@node.icon} class="size-3.5" />
          </div>
          <span class="text-sm font-semibold">{@node.label}</span>
        </div>
        <button
          phx-click="close_drawer"
          class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <%!-- Drawer body --%>
      <div class="flex-1 overflow-y-auto p-4 space-y-4">
        <.node_properties type={@node.type} data={@node.data} />
      </div>
    </aside>
    """
  end

  # ── Node-specific property forms ─────────────────────────────────────────

  attr :type, :string, required: true
  attr :data, :map, required: true

  defp node_properties(%{type: "start"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Start"}
        placeholder="Start"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Describe what triggers this flow"
        type="textarea"
      />
      <.prop_select
        label="Trigger Type"
        field="trigger_type"
        value={@data["trigger_type"] || "manual"}
        options={[{"Manual", "manual"}, {"Webhook", "webhook"}, {"Schedule", "schedule"}]}
      />
    </div>
    """
  end

  defp node_properties(%{type: "elixir_code"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Elixir Code"}
        placeholder="Elixir Code"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="What does this step do?"
        type="textarea"
      />
      <div>
        <label class="block text-xs font-medium text-muted-foreground mb-1.5">Code</label>
        <textarea
          phx-blur="update_node_data"
          phx-value-field="code"
          rows="12"
          placeholder={"# Access input with `input`\n# Return a value\n\ninput\n|> Map.get(\"data\")\n|> String.upcase()"}
          class="w-full rounded-lg border bg-background px-3 py-2 font-mono text-xs leading-relaxed focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >{@data["code"] || ""}</textarea>
      </div>
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "5000"}
        placeholder="5000"
        type="number"
      />
    </div>
    """
  end

  defp node_properties(%{type: "condition"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Condition"}
        placeholder="Condition"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Describe the branching logic"
        type="textarea"
      />
      <div>
        <label class="block text-xs font-medium text-muted-foreground mb-1.5">Expression</label>
        <textarea
          phx-blur="update_node_data"
          phx-value-field="expression"
          rows="6"
          placeholder={"# Return branch index (0-based)\n# e.g. 0 for first output, 1 for second\n\ncond do\n  input[\"status\"] == \"ok\" -> 0\n  input[\"status\"] == \"error\" -> 1\n  true -> 2\nend"}
          class="w-full rounded-lg border bg-background px-3 py-2 font-mono text-xs leading-relaxed focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >{@data["expression"] || ""}</textarea>
      </div>
      <div>
        <label class="block text-xs font-medium text-muted-foreground mb-1.5">Branch Labels</label>
        <p class="text-xs text-muted-foreground mb-2">
          Name each output branch (one per line)
        </p>
        <textarea
          phx-blur="update_node_data"
          phx-value-field="branch_labels"
          rows="4"
          placeholder="Success\nError\nDefault"
          class="w-full rounded-lg border bg-background px-3 py-2 text-xs leading-relaxed focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >{@data["branch_labels"] || ""}</textarea>
      </div>
    </div>
    """
  end

  defp node_properties(%{type: "end"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "End"}
        placeholder="End"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Describe how the flow ends"
        type="textarea"
      />
      <.prop_select
        label="Output Mode"
        field="output_mode"
        value={@data["output_mode"] || "last_value"}
        options={[
          {"Last Value", "last_value"},
          {"Accumulate All", "accumulate"},
          {"Discard", "discard"}
        ]}
      />
    </div>
    """
  end

  defp node_properties(assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || ""}
        placeholder="Node name"
      />
    </div>
    """
  end

  # ── Reusable property field components ───────────────────────────────────

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"

  defp prop_field(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label class="block text-xs font-medium text-muted-foreground mb-1.5">{@label}</label>
      <textarea
        phx-blur="update_node_data"
        phx-value-field={@field}
        rows="3"
        placeholder={@placeholder}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      >{@value}</textarea>
    </div>
    """
  end

  defp prop_field(assigns) do
    ~H"""
    <div>
      <label class="block text-xs font-medium text-muted-foreground mb-1.5">{@label}</label>
      <input
        type={@type}
        phx-blur="update_node_data"
        phx-value-field={@field}
        value={@value}
        placeholder={@placeholder}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true

  defp prop_select(assigns) do
    ~H"""
    <div>
      <label class="block text-xs font-medium text-muted-foreground mb-1.5">{@label}</label>
      <select
        phx-change="update_node_data"
        phx-value-field={@field}
        class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
      >
        <option :for={{label, val} <- @options} value={val} selected={val == @value}>
          {label}
        </option>
      </select>
    </div>
    """
  end

  # ── Node palette component ──────────────────────────────────────────────

  attr :label, :string, required: true
  attr :nodes, :list, required: true

  defp node_group(assigns) do
    ~H"""
    <div>
      <div class="px-1 pb-1.5">
        <span class="text-[0.65rem] font-semibold uppercase tracking-wider text-muted-foreground">
          {@label}
        </span>
      </div>
      <div class="space-y-1.5">
        <div
          :for={node <- @nodes}
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
    </div>
    """
  end
end
