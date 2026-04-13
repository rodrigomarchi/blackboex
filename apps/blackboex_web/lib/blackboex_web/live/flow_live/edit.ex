defmodule BlackboexWeb.FlowLive.Edit do
  @moduledoc """
  Full-screen flow editor with Drawflow canvas.
  Mounts the Drawflow JS library via phx-hook and communicates
  graph state as JSON over the LiveView socket.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows
  alias Blackboex.Policy
  alias BlackboexWeb.FlowLive.EditHelpers

  import BlackboexWeb.Components.FlowEditor.CanvasToolbar
  import BlackboexWeb.Components.FlowEditor.ExecutionsDrawer
  import BlackboexWeb.Components.FlowEditor.FlowHeader
  import BlackboexWeb.Components.FlowEditor.JsonPreviewModal
  import BlackboexWeb.Components.FlowEditor.NodePalette
  import BlackboexWeb.Components.FlowEditor.PropertiesDrawer
  import BlackboexWeb.Components.FlowEditor.RunModal

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
           node_types: EditHelpers.node_types(),
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
           confirm: nil,
           show_executions_drawer: false,
           executions: [],
           selected_execution: nil,
           expanded_exec_node: nil,
           executions_drawer_expanded: false
         )}
    end
  end

  # ── handle_params ────────────────────────────────────────────────────────

  @impl true
  def handle_params(%{"execution" => exec_id} = _params, _uri, socket) do
    if socket.assigns.selected_execution && socket.assigns.selected_execution.id == exec_id do
      {:noreply, socket}
    else
      org = socket.assigns.current_scope.organization

      case FlowExecutions.get_execution_for_org(org.id, exec_id) do
        nil ->
          {:noreply, push_patch(socket, to: ~p"/flows/#{socket.assigns.flow.id}/edit")}

        execution ->
          sorted = (execution.node_executions || []) |> Enum.sort_by(& &1.inserted_at)
          execution = %{execution | node_executions: sorted}
          node_map = Enum.map(sorted, &node_execution_to_map/1)

          {:noreply,
           socket
           |> assign(
             selected_execution: execution,
             expanded_exec_node: nil,
             show_executions_drawer: true
           )
           |> push_event("load_execution_view", %{nodes: node_map})}
      end
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    if socket.assigns.selected_execution do
      {:noreply,
       socket
       |> assign(selected_execution: nil, expanded_exec_node: nil)
       |> push_event("clear_execution_view", %{})}
    else
      {:noreply, socket}
    end
  end

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = EditHelpers.build_confirm(params["action"], params)
    {:noreply, assign(socket, confirm: confirm)}
  end

  @impl true
  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end

  @impl true
  def handle_event("execute_confirm", _params, socket) do
    case socket.assigns.confirm do
      nil ->
        {:noreply, socket}

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
    node_meta =
      Map.get(EditHelpers.node_type_map(), type, %{
        label: type,
        icon: "hero-cube",
        color: "#6b7280"
      })

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
        updated_data = EditHelpers.apply_field_update(node.data, field, value)
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
    {parent_path, index} = EditHelpers.split_path(path)

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
    {parent_path, index} = EditHelpers.split_path(path)

    update_schema_at_path(socket, schema_id, parent_path, fn fields ->
      List.update_at(fields, index, &EditHelpers.update_field_prop(&1, prop, value))
    end)
  end

  @impl true
  def handle_event(
        "schema_update_constraint",
        %{"schema-id" => schema_id, "path" => path, "prop" => prop, "value" => value},
        socket
      ) do
    {parent_path, index} = EditHelpers.split_path(path)

    update_schema_at_path(socket, schema_id, parent_path, fn fields ->
      List.update_at(fields, index, &EditHelpers.update_field_constraint(&1, prop, value))
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
        mapping =
          EditHelpers.upsert_mapping(
            node.data["response_mapping"] || [],
            response_field,
            state_var
          )

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

  # ── Executions Drawer ────────────────────────────────────────────────────

  @impl true
  def handle_event("open_executions_drawer", _params, socket) do
    executions = FlowExecutions.list_executions_for_flow(socket.assigns.flow.id)

    {:noreply,
     assign(socket,
       show_executions_drawer: true,
       executions: executions,
       selected_execution: nil,
       expanded_exec_node: nil
     )}
  end

  @impl true
  def handle_event("toggle_executions_drawer_expand", _params, socket) do
    {:noreply,
     assign(socket, executions_drawer_expanded: !socket.assigns.executions_drawer_expanded)}
  end

  @impl true
  def handle_event("close_executions_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(show_executions_drawer: false, executions_drawer_expanded: false)
     |> push_patch(to: ~p"/flows/#{socket.assigns.flow.id}/edit")}
  end

  @impl true
  def handle_event("select_execution", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/flows/#{socket.assigns.flow.id}/edit?execution=#{id}")}
  end

  @impl true
  def handle_event("deselect_execution", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/flows/#{socket.assigns.flow.id}/edit")}
  end

  @impl true
  def handle_event("toggle_exec_node", %{"node-id" => node_id}, socket) do
    expanded =
      if socket.assigns.expanded_exec_node == node_id, do: nil, else: node_id

    {:noreply, assign(socket, expanded_exec_node: expanded)}
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp node_execution_to_map(ne) do
    %{
      id: ne.node_id,
      status: ne.status,
      duration_ms: ne.duration_ms,
      input: ne.input,
      output: ne.output,
      error: ne.error
    }
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

  defp update_schema_at_path(socket, schema_id, path, update_fn) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        schema = node.data[schema_id] || []
        updated_schema = EditHelpers.apply_at_path(schema, path, update_fn)
        updated_data = Map.put(node.data, schema_id, updated_schema)
        updated_node = %{node | data: updated_data}

        {:noreply,
         socket
         |> assign(selected_node: updated_node)
         |> push_event("set_node_data", %{id: node.id, data: updated_data})}
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
      <.flow_header flow={@flow} saving={@saving} saved={@saved} />

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <.node_palette node_types={@node_types} />

        <%!-- Drawflow canvas --%>
        <div class="flex-1 relative">
          <div
            id="drawflow-canvas"
            phx-hook="DrawflowEditor"
            phx-update="ignore"
            data-definition={Jason.encode!(@flow.definition)}
            class="parent-drawflow h-full w-full relative"
          >
            <.canvas_toolbar />
          </div>
        </div>

        <%!-- Properties drawer --%>
        <.properties_drawer
          node={@selected_node}
          tab={@properties_tab}
          expanded={@drawer_expanded}
          state_variables={EditHelpers.get_state_variables(@flow, @selected_node)}
          org_flows={@org_flows}
          sub_flow_schema={@sub_flow_schema}
        />

        <%!-- Executions drawer (right of canvas) --%>
        <.executions_drawer
          show={@show_executions_drawer}
          executions={@executions}
          selected_execution={@selected_execution}
          expanded_exec_node={@expanded_exec_node}
          expanded={@executions_drawer_expanded}
        />
      </div>

      <.json_preview_modal :if={@show_json_modal} flow={@flow} json_preview={@json_preview} />

      <.run_modal
        :if={@show_run_modal}
        run_input={@run_input}
        running={@running}
        run_result={@run_result}
        run_error={@run_error}
      />

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
end
