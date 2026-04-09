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

  import BlackboexWeb.FlowLive.Components.SchemaBuilder

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
    },
    %{
      type: "http_request",
      label: "HTTP Request",
      subtitle: "Call API",
      icon: "hero-globe-alt",
      color: "#f97316",
      inputs: 1,
      outputs: 1,
      group: "integration"
    },
    %{
      type: "delay",
      label: "Delay",
      subtitle: "Wait",
      icon: "hero-clock",
      color: "#eab308",
      inputs: 1,
      outputs: 1,
      group: "control"
    },
    %{
      type: "webhook_wait",
      label: "Webhook Wait",
      subtitle: "Pause for event",
      icon: "hero-arrow-path",
      color: "#ec4899",
      inputs: 1,
      outputs: 1,
      group: "control"
    },
    %{
      type: "sub_flow",
      label: "Sub-Flow",
      subtitle: "Nested flow",
      icon: "hero-squares-2x2",
      color: "#6366f1",
      inputs: 1,
      outputs: 1,
      group: "composition"
    },
    %{
      type: "for_each",
      label: "For Each",
      subtitle: "Iterate list",
      icon: "hero-arrow-path-rounded-square",
      color: "#14b8a6",
      inputs: 1,
      outputs: 1,
      group: "composition"
    }
  ]

  @node_type_map Map.new(@node_types, fn n -> {n.type, n} end)

  # Maps synthetic auth form fields to nested auth_config keys
  @auth_field_map %{
    "auth_token" => {"auth_config", "token"},
    "auth_username" => {"auth_config", "username"},
    "auth_password" => {"auth_config", "password"},
    "auth_key_name" => {"auth_config", "key_name"},
    "auth_key_value" => {"auth_config", "key_value"}
  }

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
        org_flows =
          org.id
          |> Flows.list_flows()
          |> Enum.filter(&(&1.id != flow.id && &1.status in ~w(draft active)))
          |> Enum.map(&%{id: &1.id, name: &1.name})

        {:ok,
         assign(socket,
           flow: flow,
           page_title: flow.name,
           node_types: @node_types,
           org_flows: org_flows,
           sub_flow_schema: [],
           saving: false,
           saved: false,
           selected_node: nil,
           properties_tab: "settings",
           show_json_modal: false,
           json_preview: "",
           show_run_modal: false,
           run_input: "{}",
           run_result: nil,
           run_error: nil,
           running: false,
           run_task_ref: nil,
           drawer_expanded: false,
           confirm: nil
         )}
    end
  end

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = build_confirm(params["action"], params)
    {:noreply, assign(socket, confirm: confirm)}
  end

  @impl true
  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end

  @impl true
  def handle_event("execute_confirm", _params, socket) do
    case socket.assigns.confirm do
      nil -> {:noreply, socket}
      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
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

    # Load sub-flow payload schema when selecting a sub_flow node
    sub_flow_schema =
      if type == "sub_flow" do
        extract_payload_schema(data["flow_id"], socket)
      else
        socket.assigns.sub_flow_schema
      end

    {:noreply,
     assign(socket,
       selected_node: %{
         id: id,
         type: type,
         data: data,
         label: node_meta[:label] || type,
         icon: node_meta[:icon] || "hero-cube",
         color: node_meta[:color] || "#6b7280"
       },
       sub_flow_schema: sub_flow_schema,
       properties_tab: "settings"
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
        updated_data = apply_field_update(node.data, field, value)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, selected_node: nil, drawer_expanded: false)}
  end

  @impl true
  def handle_event("toggle_drawer_expand", _params, socket) do
    {:noreply, assign(socket, drawer_expanded: !socket.assigns.drawer_expanded)}
  end

  # ── Properties tab ──────────────────────────────────────────────────────

  @impl true
  def handle_event("set_properties_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, properties_tab: tab)}
  end

  # ── Sub-flow picker ─────────────────────────────────────────────────────

  @impl true
  def handle_event("select_sub_flow", %{"flow_id" => flow_id}, socket) do
    node = socket.assigns.selected_node

    case node do
      nil ->
        {:noreply, socket}

      _ ->
        schema = extract_payload_schema(flow_id, socket)
        updated_data = Map.put(node.data, "flow_id", flow_id)

        # Initialize input_mapping with empty values for each schema field
        existing_mapping = Map.get(node.data, "input_mapping", %{})

        input_mapping =
          Enum.reduce(schema, existing_mapping, fn field, acc ->
            Map.put_new(acc, field["name"], "")
          end)

        updated_data = Map.put(updated_data, "input_mapping", input_mapping)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node, sub_flow_schema: schema)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
  end

  @impl true
  def handle_event(
        "update_input_mapping",
        %{"field" => field, "value" => value},
        socket
      ) do
    node = socket.assigns.selected_node

    case node do
      nil ->
        {:noreply, socket}

      _ ->
        mapping = Map.get(node.data, "input_mapping", %{})
        updated_mapping = Map.put(mapping, field, value)
        updated_data = Map.put(node.data, "input_mapping", updated_mapping)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
  end

  # ── Schema builder events ───────────────────────────────────────────────

  @impl true
  def handle_event("schema_add_field", %{"schema-id" => schema_id, "path" => path}, socket) do
    new_field = %{"name" => "", "type" => "string", "required" => false, "constraints" => %{}}
    update_schema_at_path(socket, schema_id, path, fn fields -> fields ++ [new_field] end)
  end

  @impl true
  def handle_event("schema_remove_field", %{"schema-id" => schema_id, "path" => path}, socket) do
    {parent_path, index} = split_path(path)

    update_schema_at_path(socket, schema_id, parent_path, fn fields ->
      List.delete_at(fields, index)
    end)
  end

  @impl true
  def handle_event(
        "schema_update_field",
        %{"schema-id" => schema_id, "path" => path, "prop" => prop, "value" => value},
        socket
      ) do
    {parent_path, index} = split_path(path)

    update_schema_at_path(socket, schema_id, parent_path, fn fields ->
      List.update_at(fields, index, &update_field_prop(&1, prop, value))
    end)
  end

  @impl true
  def handle_event(
        "schema_update_constraint",
        %{"schema-id" => schema_id, "path" => path, "prop" => prop, "value" => value},
        socket
      ) do
    {parent_path, index} = split_path(path)

    update_schema_at_path(socket, schema_id, parent_path, fn fields ->
      List.update_at(fields, index, &update_field_constraint(&1, prop, value))
    end)
  end

  @impl true
  def handle_event(
        "schema_update_mapping",
        %{"response-field" => response_field, "value" => state_var},
        socket
      ) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        mapping = upsert_mapping(node.data["response_mapping"] || [], response_field, state_var)
        updated_data = Map.put(node.data, "response_mapping", mapping)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
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

  # ── Private helpers for handle_event ─────────────────────────────────────

  defp apply_field_update(data, field, value) do
    case Map.get(@auth_field_map, field) do
      {parent_key, nested_key} ->
        parent = Map.get(data, parent_key, %{})
        Map.put(data, parent_key, Map.put(parent, nested_key, value))

      nil ->
        Map.put(data, field, value)
    end
  end

  defp extract_payload_schema("", _socket), do: []
  defp extract_payload_schema(nil, _socket), do: []

  defp extract_payload_schema(flow_id, socket) do
    org = socket.assigns.current_scope.organization

    case org && Flows.get_flow(org.id, flow_id) do
      nil ->
        []

      flow ->
        (flow.definition || %{})
        |> Map.get("nodes", [])
        |> Enum.find(fn n -> n["type"] == "start" end)
        |> case do
          nil -> []
          start_node -> get_in(start_node, ["data", "payload_schema"]) || []
        end
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
          <.link navigate={~p"/"} class="text-foreground hover:text-foreground/80">
            <.logo_icon class="size-7" />
          </.link>
          <.link navigate={~p"/flows"} class="text-muted-foreground hover:text-foreground">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-sm font-semibold truncate max-w-xs">{@flow.name}</h1>
          <%= if @flow.status == "active" do %>
            <span class="inline-flex items-center gap-1.5 rounded-full bg-green-500/15 px-2.5 py-0.5 text-xs font-medium text-green-600 dark:text-green-400">
              <span class="size-1.5 rounded-full bg-green-500 animate-pulse" />
              active
            </span>
            <button
              phx-click="deactivate_flow"
              class="inline-flex items-center gap-1 rounded-full bg-muted/50 px-2.5 py-1 text-xs text-muted-foreground hover:bg-orange-500/15 hover:text-orange-500 transition-colors"
            >
              <.icon name="hero-pause-circle-mini" class="size-3.5" /> Pause
            </button>
          <% else %>
            <span class="inline-flex items-center gap-1.5 rounded-full bg-muted px-2.5 py-0.5 text-xs font-medium text-muted-foreground">
              <span class="size-1.5 rounded-full bg-gray-400" />
              draft
            </span>
            <button
              phx-click="activate_flow"
              class="inline-flex items-center gap-1 rounded-full bg-green-500/15 px-2.5 py-1 text-xs text-green-600 dark:text-green-400 hover:bg-green-500/25 transition-colors"
            >
              <.icon name="hero-bolt-mini" class="size-3.5" /> Activate
            </button>
          <% end %>
        </div>

        <div class="flex items-center gap-2">
          <%!-- Webhook URL --%>
          <div class="hidden md:flex items-center gap-1 rounded border bg-muted/50 px-2 py-1">
            <.icon name="hero-link-mini" class="size-3.5 text-emerald-400 shrink-0" />
            <span class="text-[0.65rem] text-muted-foreground font-mono truncate max-w-[200px]">
              /webhook/{String.slice(@flow.webhook_token, 0..7)}...
            </span>
            <button
              phx-click={JS.dispatch("phx:copy_to_clipboard", detail: %{text: webhook_url(@flow)})}
              class="p-0.5 text-muted-foreground hover:text-foreground"
              title="Copy webhook URL"
            >
              <.icon name="hero-clipboard-document" class="size-3.5 text-sky-400" />
            </button>
            <button
              phx-click="request_confirm"
              phx-value-action="regenerate_token"
              class="p-0.5 text-muted-foreground hover:text-foreground"
              title="Regenerate token"
            >
              <.icon name="hero-arrow-path" class="size-3.5 text-amber-400" />
            </button>
          </div>

          <span :if={@saved} class="text-xs text-green-600 dark:text-green-400">Saved</span>

          <.button variant="outline" size="sm" navigate={~p"/flows/#{@flow.id}/executions"}>
            <.icon name="hero-clock" class="mr-1.5 size-4 text-sky-400" /> History
          </.button>
          <.button variant="outline" size="sm" phx-click="open_run_modal">
            <.icon name="hero-play" class="mr-1.5 size-4 text-green-400" /> Run
          </.button>
          <.button variant="outline" size="sm" phx-click="request_json_preview">
            <.icon name="hero-code-bracket" class="mr-1.5 size-4 text-violet-400" /> JSON
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
              <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-emerald-300" /> Save
            <% end %>
          </.button>
        </div>
      </header>

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <%!-- Node palette sidebar (icon-only) --%>
        <aside class="flex w-14 shrink-0 flex-col items-center border-r bg-card py-2 gap-1 overflow-y-auto">
          <div
            :for={node <- @node_types}
            draggable="true"
            data-node-type={node.type}
            data-node-label={node.label}
            data-node-inputs={node.inputs}
            data-node-outputs={node.outputs}
            title={node.label}
            class="flex size-9 cursor-grab items-center justify-center rounded-lg border border-transparent hover:border-primary/50 hover:shadow-sm active:cursor-grabbing transition-all"
            style={"color: #{node.color}"}
          >
            <.icon name={node.icon} class="size-5" />
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
        <.properties_drawer
          node={@selected_node}
          tab={@properties_tab}
          expanded={@drawer_expanded}
          state_variables={get_state_variables(@flow, @selected_node)}
          org_flows={@org_flows}
          sub_flow_schema={@sub_flow_schema}
        />
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
                <.icon name="hero-code-bracket" class="size-5 text-violet-400" />
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
                  <.icon name="hero-clipboard-document" class="mr-1.5 size-4 text-sky-400" /> Copy
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
                  <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-emerald-400" /> Download
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
                class="w-full h-full rounded-lg overflow-hidden"
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
                  style="height: 120px;"
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
                  <.icon name="hero-play" class="mr-1.5 size-4 text-green-400" /> Execute
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

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />
    </div>
    """
  end

  defp build_confirm("regenerate_token", _params) do
    %{
      title: "Regenerate webhook token?",
      description: "The current webhook URL will immediately stop working. Any integrations using it will need to be updated.",
      variant: :warning,
      confirm_label: "Regenerate",
      event: "regenerate_token",
      meta: %{}
    }
  end

  defp build_confirm(_, _), do: nil

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
  attr :tab, :string, default: "settings"
  attr :expanded, :boolean, default: false
  attr :state_variables, :list, default: []
  attr :org_flows, :list, default: []
  attr :sub_flow_schema, :list, default: []

  defp properties_drawer(%{node: nil} = assigns) do
    ~H"""
    """
  end

  defp properties_drawer(assigns) do
    width_class = if assigns.expanded, do: "w-[70vw]", else: "w-96"

    assigns = assign(assigns, width_class: width_class)

    ~H"""
    <aside class={"flex shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200 #{@width_class} transition-[width] ease-in-out"}>
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
        <div class="flex items-center gap-1">
          <button
            phx-click="toggle_drawer_expand"
            class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
            title={if @expanded, do: "Collapse", else: "Expand"}
          >
            <.icon
              name={if @expanded, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="size-4"
            />
          </button>
          <button
            phx-click="close_drawer"
            class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Drawer body --%>
      <div class="flex-1 overflow-y-auto p-4 space-y-4">
        <.node_properties
          type={@node.type}
          data={@node.data}
          node_id={@node.id}
          tab={@tab}
          state_variables={@state_variables}
          org_flows={@org_flows}
          sub_flow_schema={@sub_flow_schema}
        />
      </div>
    </aside>
    """
  end

  # ── Node-specific property forms ─────────────────────────────────────────

  attr :type, :string, required: true
  attr :data, :map, required: true
  attr :node_id, :string, required: true
  attr :tab, :string, default: "settings"
  attr :state_variables, :list, default: []
  attr :org_flows, :list, default: []
  attr :sub_flow_schema, :list, default: []

  defp node_properties(%{type: "start"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs
        tabs={[
          {"Settings", "settings"},
          {"Payload Schema", "payload_schema"},
          {"State Schema", "state_schema"}
        ]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "Start"}
          placeholder="Start"
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_field
          label="Description"
          field="description"
          value={@data["description"] || ""}
          placeholder="Describe what triggers this flow"
          type="textarea"
          icon="hero-chat-bubble-bottom-center-text"
          icon_color="text-sky-400"
        />
        <.prop_select
          label="Execution Mode"
          field="execution_mode"
          value={@data["execution_mode"] || "sync"}
          options={[{"Sync (request/response)", "sync"}, {"Async (polling)", "async"}]}
          icon="hero-bolt"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "30000"}
          placeholder="30000"
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
        <.prop_select
          label="Trigger Type"
          field="trigger_type"
          value={@data["trigger_type"] || "webhook"}
          options={[{"Webhook", "webhook"}, {"Manual", "manual"}, {"Schedule", "schedule"}]}
          icon="hero-signal"
          icon_color="text-green-400"
        />
      </div>

      <div :if={@tab == "payload_schema"}>
        <.schema_builder
          schema_id="payload_schema"
          fields={@data["payload_schema"] || []}
          label="Payload Fields"
        />
      </div>

      <div :if={@tab == "state_schema"}>
        <.schema_builder
          schema_id="state_schema"
          fields={@data["state_schema"] || []}
          show_initial_value={true}
          label="State Variables"
        />
      </div>
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
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="What does this step do?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-code-bracket" class="size-3.5 text-purple-400" /> Code
        </label>
        <div
          id={"code-editor-#{@node_id}-code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="code"
          data-value={@data["code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 240px;"
        />
      </div>
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "5000"}
        placeholder="5000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
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
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Describe the branching logic"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-code-bracket" class="size-3.5 text-blue-400" /> Expression
        </label>
        <div
          id={"code-editor-#{@node_id}-expression"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="expression"
          data-value={@data["expression"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 120px;"
        />
      </div>
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
          <.icon name="hero-tag" class="size-3.5 text-teal-400" /> Branch Labels
        </label>
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
      <.properties_tabs
        tabs={[{"Settings", "settings"}, {"Response Schema", "response_schema"}]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "End"}
          placeholder="End"
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_field
          label="Description"
          field="description"
          value={@data["description"] || ""}
          placeholder="Describe how the flow ends"
          type="textarea"
          icon="hero-chat-bubble-bottom-center-text"
          icon_color="text-sky-400"
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
          icon="hero-arrow-down-tray"
          icon_color="text-emerald-400"
        />
      </div>

      <div :if={@tab == "response_schema"} class="space-y-4">
        <.schema_builder
          schema_id="response_schema"
          fields={@data["response_schema"] || []}
          label="Response Fields"
        />
        <.response_mapping
          mapping={@data["response_mapping"] || []}
          response_schema={@data["response_schema"] || []}
          state_variables={@state_variables}
        />
      </div>
    </div>
    """
  end

  defp node_properties(%{type: "http_request"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs
        tabs={[{"Settings", "settings"}, {"Auth", "auth"}, {"Advanced", "advanced"}]}
        active={@tab}
      />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "HTTP Request"}
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <.prop_select
          label="Method"
          field="method"
          value={@data["method"] || "GET"}
          options={[
            {"GET", "GET"},
            {"POST", "POST"},
            {"PUT", "PUT"},
            {"PATCH", "PATCH"},
            {"DELETE", "DELETE"}
          ]}
          icon="hero-command-line"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="URL"
          field="url"
          value={@data["url"] || ""}
          placeholder="https://api.example.com/{{state.path}}"
          icon="hero-link"
          icon_color="text-blue-400"
        />
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5"><.icon name="hero-document-text" class="size-3.5 text-emerald-400" /> Body Template</label>
          <div
            id={"code-editor-#{@node_id}-body_template"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="json"
            data-event="update_node_data"
            data-field="body_template"
            data-value={@data["body_template"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 120px;"
          />
        </div>
      </div>

      <div :if={@tab == "auth"} class="space-y-4">
        <.prop_select
          label="Auth Type"
          field="auth_type"
          value={@data["auth_type"] || "none"}
          options={[
            {"None", "none"},
            {"Bearer Token", "bearer"},
            {"Basic Auth", "basic"},
            {"API Key", "api_key"}
          ]}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "bearer"}
          label="Token"
          field="auth_token"
          value={get_in(@data, ["auth_config", "token"]) || ""}
          placeholder="Bearer token"
          icon="hero-key"
          icon_color="text-amber-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Username"
          field="auth_username"
          value={get_in(@data, ["auth_config", "username"]) || ""}
          icon="hero-user"
          icon_color="text-sky-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "basic"}
          label="Password"
          field="auth_password"
          value={get_in(@data, ["auth_config", "password"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Name"
          field="auth_key_name"
          value={get_in(@data, ["auth_config", "key_name"]) || ""}
          placeholder="X-API-Key"
          icon="hero-key"
          icon_color="text-amber-400"
        />
        <.prop_field
          :if={@data["auth_type"] == "api_key"}
          label="Key Value"
          field="auth_key_value"
          value={get_in(@data, ["auth_config", "key_value"]) || ""}
          icon="hero-lock-closed"
          icon_color="text-rose-400"
        />
      </div>

      <div :if={@tab == "advanced"} class="space-y-4">
        <.prop_field
          label="Timeout (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "10000"}
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
        <.prop_field
          label="Max Retries"
          field="max_retries"
          value={@data["max_retries"] || "3"}
          type="number"
          icon="hero-arrow-path"
          icon_color="text-cyan-400"
        />
        <.prop_field
          label="Expected Status Codes"
          field="expected_status"
          value={format_status_codes(@data["expected_status"])}
          placeholder="200, 201"
          icon="hero-check-badge"
          icon_color="text-green-400"
        />
      </div>
    </div>
    """
  end

  defp node_properties(%{type: "delay"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Delay"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Duration (ms)"
        field="duration_ms"
        value={@data["duration_ms"] || "1000"}
        placeholder="1000"
        type="number"
        icon="hero-clock"
        icon_color="text-amber-400"
      />
      <.prop_field
        label="Max Duration (ms)"
        field="max_duration_ms"
        value={@data["max_duration_ms"] || "60000"}
        placeholder="60000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <.prop_field
        label="Description"
        field="description"
        value={@data["description"] || ""}
        placeholder="Why is this delay needed?"
        type="textarea"
        icon="hero-chat-bubble-bottom-center-text"
        icon_color="text-sky-400"
      />
    </div>
    """
  end

  defp node_properties(%{type: "sub_flow"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Sub-Flow"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />

      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5"><.icon name="hero-squares-2x2" class="size-3.5 text-indigo-400" /> Sub-Flow</label>
        <select
          phx-change="select_sub_flow"
          name="flow_id"
          class="w-full rounded-lg border bg-background px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">Select a flow...</option>
          <option
            :for={flow <- @org_flows}
            value={flow.id}
            selected={flow.id == @data["flow_id"]}
          >
            {flow.name}
          </option>
        </select>
      </div>

      <%= if @data["flow_id"] && @data["flow_id"] != "" do %>
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-2">
            <.icon name="hero-arrows-right-left" class="size-3.5 text-teal-400" /> Input Mapping
          </label>
          <p class="text-xs text-muted-foreground mb-3">
            Map parent flow state/input to sub-flow payload fields
          </p>

          <%= if (@sub_flow_schema) == [] do %>
            <p class="text-xs text-muted-foreground italic">
              Selected flow has no payload schema defined.
              You can still add custom mappings below.
            </p>
          <% end %>

          <div class="space-y-3">
            <div
              :for={field <- @sub_flow_schema}
              class="space-y-1"
            >
              <div class="flex items-center gap-1.5">
                <span class="text-xs font-medium text-foreground">{field["name"]}</span>
                <span class="text-xs text-muted-foreground">({field["type"]})</span>
                <span class="text-xs text-muted-foreground">&larr;</span>
              </div>
              <div
                id={"code-editor-#{@node_id}-mapping-#{field["name"]}"}
                phx-hook="CodeEditor"
                phx-update="ignore"
                data-language="elixir"
                data-minimal="true"
                data-event="update_input_mapping"
                data-field={field["name"]}
                data-value={get_in(@data, ["input_mapping", field["name"]]) || ""}
                class="w-full rounded-lg border overflow-hidden"
                style="height: 36px;"
              />
            </div>
          </div>
        </div>
      <% end %>

      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "30000"}
        placeholder="30000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
    </div>
    """
  end

  defp node_properties(%{type: "for_each"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.properties_tabs tabs={[{"Settings", "settings"}, {"Code", "code"}]} active={@tab} />

      <div :if={@tab == "settings"} class="space-y-4">
        <.prop_field
          label="Node Name"
          field="name"
          value={@data["name"] || "For Each"}
          icon="hero-tag"
          icon_color="text-violet-400"
        />
        <div>
          <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
            <.icon name="hero-funnel" class="size-3.5 text-teal-400" /> Source Expression
          </label>
          <div
            id={"code-editor-#{@node_id}-source_expression"}
            phx-hook="CodeEditor"
            phx-update="ignore"
            data-language="elixir"
            data-event="update_node_data"
            data-field="source_expression"
            data-value={@data["source_expression"] || ""}
            class="w-full rounded-lg border overflow-hidden"
            style="height: 60px;"
          />
        </div>
        <.prop_field
          label="Item Variable"
          field="item_variable"
          value={@data["item_variable"] || "item"}
          placeholder="item"
          icon="hero-variable"
          icon_color="text-purple-400"
        />
        <.prop_field
          label="Accumulator Key"
          field="accumulator"
          value={@data["accumulator"] || "results"}
          placeholder="results"
          icon="hero-archive-box"
          icon_color="text-amber-400"
        />
        <.prop_field
          label="Batch Size"
          field="batch_size"
          value={@data["batch_size"] || "10"}
          placeholder="10"
          type="number"
          icon="hero-squares-2x2"
          icon_color="text-indigo-400"
        />
        <.prop_field
          label="Timeout per Item (ms)"
          field="timeout_ms"
          value={@data["timeout_ms"] || "5000"}
          placeholder="5000"
          type="number"
          icon="hero-clock"
          icon_color="text-orange-400"
        />
      </div>

      <div :if={@tab == "code"}>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5"><.icon name="hero-code-bracket" class="size-3.5 text-purple-400" /> Body Code</label>
        <div
          id={"code-editor-#{@node_id}-body_code"}
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="elixir"
          data-event="update_node_data"
          data-field="body_code"
          data-value={@data["body_code"] || ""}
          class="w-full rounded-lg border overflow-hidden"
          style="height: 200px;"
        />
      </div>
    </div>
    """
  end

  defp node_properties(%{type: "webhook_wait"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.prop_field
        label="Node Name"
        field="name"
        value={@data["name"] || "Webhook Wait"}
        icon="hero-tag"
        icon_color="text-violet-400"
      />
      <.prop_field
        label="Event Type"
        field="event_type"
        value={@data["event_type"] || ""}
        placeholder="e.g. approval, payment.confirmed"
        icon="hero-bell-alert"
        icon_color="text-pink-400"
      />
      <.prop_field
        label="Timeout (ms)"
        field="timeout_ms"
        value={@data["timeout_ms"] || "3600000"}
        placeholder="3600000"
        type="number"
        icon="hero-clock"
        icon_color="text-orange-400"
      />
      <.prop_field
        label="Resume Path"
        field="resume_path"
        value={@data["resume_path"] || ""}
        placeholder="e.g. data.approved"
        icon="hero-arrow-right-circle"
        icon_color="text-emerald-400"
      />
      <div>
        <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5"><.icon name="hero-link" class="size-3.5 text-blue-400" /> Callback URL</label>
        <p class="rounded-lg border bg-muted/50 px-3 py-2 text-xs text-muted-foreground font-mono">
          POST /webhook/:token/resume/{@data["event_type"] || "<event_type>"}
        </p>
      </div>
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

  defp format_status_codes(codes) when is_list(codes), do: Enum.join(codes, ", ")
  defp format_status_codes(_), do: "200, 201"

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-blue-400"

  defp prop_field(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
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
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
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
  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-blue-400"

  defp prop_select(assigns) do
    ~H"""
    <div>
      <label class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5">
        <.icon :if={@icon} name={@icon} class={"size-3.5 #{@icon_color}"} />
        {@label}
      </label>
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

  # ── Properties tab bar ───────────────────────────────────────────────────

  attr :tabs, :list, required: true
  attr :active, :string, required: true

  defp properties_tabs(assigns) do
    ~H"""
    <div class="flex border-b -mx-4 px-4">
      <button
        :for={{label, id} <- @tabs}
        type="button"
        phx-click="set_properties_tab"
        phx-value-tab={id}
        class={[
          "px-3 py-2 text-xs font-medium border-b-2 -mb-px transition-colors",
          if(id == @active,
            do: "border-primary text-foreground",
            else:
              "border-transparent text-muted-foreground hover:text-foreground hover:border-muted-foreground/50"
          )
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  # ── Schema builder helpers ──────────────────────────────────────────────

  defp update_schema_at_path(socket, schema_id, path, update_fn) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        schema = node.data[schema_id] || []
        updated_schema = apply_at_path(schema, path, update_fn)
        updated_data = Map.put(node.data, schema_id, updated_schema)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
    end
  end

  # Navigate into nested fields/item_fields via dot-separated path
  defp apply_at_path(fields, "", update_fn), do: update_fn.(fields)

  defp apply_at_path(fields, path, update_fn) do
    segments = String.split(path, ".")

    do_apply_at_path(fields, segments, update_fn)
  end

  defp do_apply_at_path(fields, [], update_fn), do: update_fn.(fields)

  defp do_apply_at_path(fields, [segment | rest], update_fn) when is_list(fields) do
    case Integer.parse(segment) do
      {index, ""} ->
        List.update_at(fields, index, fn field ->
          do_apply_at_path(field, rest, update_fn)
        end)

      _ ->
        # It's a key like "fields" or "constraints" — navigate into the map
        fields
    end
  end

  defp do_apply_at_path(%{} = map, [key | rest], update_fn) do
    current = Map.get(map, key, [])
    Map.put(map, key, do_apply_at_path(current, rest, update_fn))
  end

  defp do_apply_at_path(other, _segments, _update_fn), do: other

  defp split_path(path) do
    parts = String.split(path, ".")
    index = parts |> List.last() |> String.to_integer()
    parent = parts |> Enum.drop(-1) |> Enum.join(".")
    {parent, index}
  end

  defp update_field_prop(field, prop, value) do
    parsed_value = parse_field_prop(prop, value, field)
    field = Map.put(field, prop, parsed_value)

    if prop == "type" do
      field
      |> Map.put("constraints", default_constraints(parsed_value))
      |> maybe_remove_fields(parsed_value)
    else
      field
    end
  end

  defp update_field_constraint(field, prop, value) do
    constraints = field["constraints"] || %{}
    parsed = parse_constraint_value(prop, value)

    constraints =
      if parsed == nil or parsed == "" do
        Map.delete(constraints, prop)
      else
        Map.put(constraints, prop, parsed)
      end

    Map.put(field, "constraints", constraints)
  end

  defp upsert_mapping(mapping, response_field, "") do
    Enum.reject(mapping, &(&1["response_field"] == response_field))
  end

  defp upsert_mapping(mapping, response_field, state_var) do
    entry = %{"response_field" => response_field, "state_variable" => state_var}

    case Enum.find_index(mapping, &(&1["response_field"] == response_field)) do
      nil -> mapping ++ [entry]
      idx -> List.replace_at(mapping, idx, entry)
    end
  end

  defp parse_field_prop("required", "true", _field), do: true
  defp parse_field_prop("required", "false", _field), do: false

  defp parse_field_prop("initial_value", value, %{"type" => "integer"}) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_field_prop("initial_value", value, %{"type" => "float"}) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_field_prop("initial_value", "true", %{"type" => "boolean"}), do: true
  defp parse_field_prop("initial_value", "false", %{"type" => "boolean"}), do: false

  defp parse_field_prop("initial_value", value, %{"type" => type})
       when type in ["array", "object"] do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      _ -> nil
    end
  end

  defp parse_field_prop(_prop, value, _field), do: value

  defp parse_constraint_value(prop, value)
       when prop in ~w(min_length max_length min_items max_items) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_constraint_value(prop, value) when prop in ~w(min max) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_constraint_value("enum", value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_constraint_value(_prop, value), do: value

  defp default_constraints("array"), do: %{"item_type" => "string"}
  defp default_constraints(_), do: %{}

  defp maybe_remove_fields(field, type) when type in ~w(string integer float boolean array) do
    Map.delete(field, "fields")
  end

  defp maybe_remove_fields(field, _type), do: field

  defp get_state_variables(flow, selected_node) do
    # Prefer live editor state from selected start node, fall back to saved definition
    case selected_node do
      %{type: "start", data: %{"state_schema" => schema}} when is_list(schema) ->
        extract_variable_names(schema)

      _ ->
        extract_state_variables_from_definition(flow.definition)
    end
  end

  defp extract_state_variables_from_definition(%{"nodes" => nodes}) when is_list(nodes) do
    nodes
    |> Enum.find(&(&1["type"] == "start"))
    |> case do
      %{"data" => %{"state_schema" => schema}} when is_list(schema) ->
        extract_variable_names(schema)

      _ ->
        []
    end
  end

  defp extract_state_variables_from_definition(_), do: []

  defp extract_variable_names(schema) do
    schema |> Enum.map(& &1["name"]) |> Enum.filter(&is_binary/1)
  end
end
