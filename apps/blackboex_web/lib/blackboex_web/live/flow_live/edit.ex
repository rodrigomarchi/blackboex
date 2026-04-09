defmodule BlackboexWeb.FlowLive.Edit do
  @moduledoc """
  Full-screen flow editor with Drawflow canvas.
  Mounts the Drawflow JS library via phx-hook and communicates
  graph state as JSON over the LiveView socket.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
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
      outputs: 3,
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
           json_preview: "",
           show_run_modal: false,
           run_input: "{}",
           run_result: nil,
           run_error: nil,
           running: false,
           run_task_ref: nil
         )}
    end
  end

  # ── Save ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("save_definition", %{"definition" => definition}, socket) do
    flow = socket.assigns.flow
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- BlackboexFlow.validate(definition),
         :ok <- Policy.authorize_and_track(:flow_update, scope, org) do
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
      {:error, reason} when is_binary(reason) ->
        {:noreply,
         socket
         |> assign(saving: false)
         |> put_flash(:error, "Invalid flow: #{reason}")}

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

  # ── Test Run ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_run_modal", _params, socket) do
    {:noreply, assign(socket, show_run_modal: true, run_result: nil, run_error: nil)}
  end

  @impl true
  def handle_event("close_run_modal", _params, socket) do
    {:noreply, assign(socket, show_run_modal: false)}
  end

  @impl true
  def handle_event("update_run_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, run_input: value)}
  end

  @impl true
  def handle_event("execute_test_run", _params, socket) do
    flow = socket.assigns.flow

    case Jason.decode(socket.assigns.run_input) do
      {:ok, input} when is_map(input) ->
        # Run async to avoid blocking the LiveView process
        task =
          Task.Supervisor.async_nolink(Blackboex.TaskSupervisor, fn ->
            FlowExecutor.execute_sync(flow, input)
          end)

        {:noreply,
         socket
         |> assign(running: true, run_result: nil, run_error: nil, run_task_ref: task.ref)}

      {:ok, _} ->
        {:noreply, assign(socket, run_error: "Input must be a JSON object")}

      {:error, _} ->
        {:noreply, assign(socket, run_error: "Invalid JSON")}
    end
  end

  # ── Webhook Token ───────────────────────────────────────────────────────

  @impl true
  def handle_event("regenerate_token", _params, socket) do
    flow = socket.assigns.flow

    case Flows.regenerate_webhook_token(flow) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(flow: updated_flow)
         |> put_flash(:info, "Webhook token regenerated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not regenerate token.")}
    end
  end

  # ── Activation ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("activate_flow", _params, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    flow = socket.assigns.flow

    with :ok <- Policy.authorize_and_track(:flow_update, scope, org) do
      # Reload flow from DB to ensure we validate the latest saved definition
      flow = Flows.get_flow(org.id, flow.id)

      case Flows.activate_flow(flow) do
        {:ok, updated_flow} ->
          {:noreply,
           socket
           |> assign(flow: updated_flow)
           |> put_flash(:info, "Flow activated. Webhook is now live.")}

        {:error, reason} when is_binary(reason) ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Cannot activate: #{reason}. Save the flow first if you have unsaved changes."
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not activate flow.")}
      end
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  @impl true
  def handle_event("deactivate_flow", _params, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    flow = socket.assigns.flow

    with :ok <- Policy.authorize_and_track(:flow_update, scope, org) do
      case Flows.deactivate_flow(flow) do
        {:ok, updated_flow} ->
          {:noreply,
           socket
           |> assign(flow: updated_flow)
           |> put_flash(:info, "Flow deactivated.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not deactivate flow.")}
      end
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  # ── Async Task Results ─────────────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, socket) when socket.assigns.run_task_ref == ref do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, run_result} ->
        {:noreply, assign(socket, running: false, run_result: run_result, run_task_ref: nil)}

      {:error, %{error: error_msg}} ->
        {:noreply, assign(socket, running: false, run_error: error_msg, run_task_ref: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, running: false, run_error: inspect(reason), run_task_ref: nil)}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
      when socket.assigns.run_task_ref == ref do
    {:noreply,
     assign(socket,
       running: false,
       run_error: "Test run crashed: #{inspect(reason)}",
       run_task_ref: nil
     )}
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
          <span class={"rounded px-2 py-0.5 text-xs #{status_badge_classes(@flow.status)}"}>
            {@flow.status}
          </span>
          <%= if @flow.status == "active" do %>
            <.button
              variant="outline"
              size="sm"
              phx-click="deactivate_flow"
              class="text-orange-600 border-orange-300 hover:bg-orange-50 dark:hover:bg-orange-950"
            >
              <.icon name="hero-pause" class="mr-1 size-3.5" /> Deactivate
            </.button>
          <% else %>
            <.button
              variant="outline"
              size="sm"
              phx-click="activate_flow"
              class="text-green-600 border-green-300 hover:bg-green-50 dark:hover:bg-green-950"
            >
              <.icon name="hero-bolt" class="mr-1 size-3.5" /> Activate
            </.button>
          <% end %>
        </div>

        <div class="flex items-center gap-2">
          <%!-- Webhook URL --%>
          <div class="hidden md:flex items-center gap-1 rounded border bg-muted/50 px-2 py-1">
            <span class="text-[0.65rem] text-muted-foreground font-mono truncate max-w-[200px]">
              /webhook/{String.slice(@flow.webhook_token, 0..7)}...
            </span>
            <button
              phx-click={JS.dispatch("phx:copy_to_clipboard", detail: %{text: webhook_url(@flow)})}
              class="p-0.5 text-muted-foreground hover:text-foreground"
              title="Copy webhook URL"
            >
              <.icon name="hero-clipboard-document" class="size-3.5" />
            </button>
            <button
              phx-click="regenerate_token"
              class="p-0.5 text-muted-foreground hover:text-foreground"
              title="Regenerate token"
              data-confirm="Regenerate webhook token? The old URL will stop working."
            >
              <.icon name="hero-arrow-path" class="size-3.5" />
            </button>
          </div>

          <span :if={@saved} class="text-xs text-green-600 dark:text-green-400">Saved</span>

          <.button variant="outline" size="sm" navigate={~p"/flows/#{@flow.id}/executions"}>
            <.icon name="hero-clock" class="mr-1.5 size-4" /> History
          </.button>
          <.button variant="outline" size="sm" phx-click="open_run_modal">
            <.icon name="hero-play" class="mr-1.5 size-4" /> Run
          </.button>
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
              <div
                id="code-editor-json-preview"
                phx-hook="CodeEditor"
                data-language="json"
                data-readonly="true"
                data-value={@json_preview}
                class="w-full rounded-lg overflow-hidden"
                style="min-height: 200px;"
              />
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Test Run Modal --%>
      <%= if @show_run_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div
            class="flex flex-col w-[600px] max-h-[80vh] rounded-xl border bg-card shadow-2xl"
            phx-click-away="close_run_modal"
          >
            <div class="flex items-center justify-between border-b px-5 py-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-play" class="size-5 text-green-500" />
                <h2 class="text-sm font-semibold">Test Run</h2>
              </div>
              <button
                phx-click="close_run_modal"
                class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <div class="flex-1 overflow-auto p-5 space-y-4">
              <div>
                <label class="block text-xs font-medium text-muted-foreground mb-1.5">
                  Input (JSON)
                </label>
                <div
                  id="code-editor-run-input"
                  phx-hook="CodeEditor"
                  phx-update="ignore"
                  data-language="json"
                  data-event="update_run_input"
                  data-value={@run_input}
                  class="w-full rounded-lg border overflow-hidden"
                  style="min-height: 120px;"
                />
              </div>
              <.button
                variant="primary"
                size="sm"
                phx-click="execute_test_run"
                disabled={@running}
              >
                <%= if @running do %>
                  <.icon name="hero-arrow-path" class="mr-1.5 size-4 animate-spin" /> Running...
                <% else %>
                  <.icon name="hero-play" class="mr-1.5 size-4" /> Execute
                <% end %>
              </.button>

              <%= if @run_error do %>
                <div class="rounded-lg border border-destructive/50 bg-destructive/5 p-3">
                  <p class="text-xs font-medium text-destructive">Error</p>
                  <pre class="mt-1 text-xs text-destructive/80 whitespace-pre-wrap"><%= @run_error %></pre>
                </div>
              <% end %>

              <%= if @run_result do %>
                <div class="rounded-lg border border-green-500/50 bg-green-500/5 p-3 space-y-2">
                  <div class="flex items-center justify-between">
                    <p class="text-xs font-medium text-green-600">Success</p>
                    <span class="text-[0.65rem] text-muted-foreground">
                      {@run_result[:duration_ms]}ms
                    </span>
                  </div>
                  <pre class="text-xs font-mono leading-relaxed text-foreground whitespace-pre-wrap"><%= Jason.encode!(@run_result[:output], pretty: true) %></pre>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp webhook_url(flow) do
    BlackboexWeb.Endpoint.url() <> "/webhook/#{flow.webhook_token}"
  end

  defp status_badge_classes("active"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp status_badge_classes("archived"),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp status_badge_classes(_), do: "bg-muted text-muted-foreground"

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
        <.node_properties type={@node.type} data={@node.data} node_id={@node.id} />
      </div>
    </aside>
    """
  end

  # ── Node-specific property forms ─────────────────────────────────────────

  attr :type, :string, required: true
  attr :data, :map, required: true
  attr :node_id, :string, required: true

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
        label="Execution Mode"
        field="execution_mode"
        value={@data["execution_mode"] || "sync"}
        options={[{"Sync (request/response)", "sync"}, {"Async (polling)", "async"}]}
      />
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "30000"}
        placeholder="30000"
        type="number"
      />
      <.prop_select
        label="Trigger Type"
        field="trigger_type"
        value={@data["trigger_type"] || "webhook"}
        options={[{"Webhook", "webhook"}, {"Manual", "manual"}, {"Schedule", "schedule"}]}
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
        <div
          id={"code-editor-#{@node_id}-code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="code"
          data-value={@data["code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="min-height: 240px;"
        />
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
        <div
          id={"code-editor-#{@node_id}-expression"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="expression"
          data-value={@data["expression"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="min-height: 120px;"
        />
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
        ><%= format_branch_labels(@data["branch_labels"]) %></textarea>
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

  defp format_branch_labels(labels) when is_map(labels) do
    labels
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map_join("\n", fn {_k, v} -> v end)
  end

  defp format_branch_labels(labels) when is_binary(labels), do: labels
  defp format_branch_labels(_), do: ""

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
