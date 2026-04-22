defmodule BlackboexWeb.FlowLive.Edit do
  @moduledoc """
  Full-screen flow editor with Drawflow canvas.
  Mounts the Drawflow JS library via phx-hook and communicates
  graph state as JSON over the LiveView socket.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.FlowAgent
  alias Blackboex.FlowConversations
  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows
  alias Blackboex.Flows.SampleInput
  alias Blackboex.Policy
  alias BlackboexWeb.FlowLive.EditHelpers
  alias BlackboexWeb.FlowLive.ExecutionGraphMerger

  import BlackboexWeb.Components.FlowEditor.CanvasToolbar
  import BlackboexWeb.Components.FlowEditor.ExecutionsDrawer
  import BlackboexWeb.Components.FlowEditor.FlowChatDrawer
  import BlackboexWeb.Components.FlowEditor.FlowHeader
  import BlackboexWeb.Components.FlowEditor.JsonPreviewModal
  import BlackboexWeb.Components.FlowEditor.NodePalette
  import BlackboexWeb.Components.FlowEditor.PropertiesDrawer
  import BlackboexWeb.Components.FlowEditor.RunDrawer

  @chat_message_cap 200
  # UI safety net: if no terminal broadcast arrives, reset chat_loading so the
  # user isn't stuck with a phantom spinner.
  @chat_timeout_ms :timer.seconds(200)

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

        chat_messages = load_chat_history(flow.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")
        end

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
           show_run_drawer: false,
           run_input: "{}",
           run_error: nil,
           running: false,
           run_task_ref: nil,
           drawer_expanded: false,
           confirm: nil,
           show_executions_drawer: false,
           executions: [],
           selected_execution: nil,
           expanded_exec_node: nil,
           executions_drawer_expanded: false,
           chat_open: false,
           chat_messages: chat_messages,
           chat_input: "",
           chat_loading: false,
           current_run_id: nil,
           current_stream: nil,
           chat_timeout_ref: nil
         )}
    end
  end

  defp load_chat_history(flow_id) do
    flow_id
    |> FlowConversations.list_active_conversation_events(limit: @chat_message_cap)
    |> Enum.flat_map(&event_to_message/1)
  end

  defp event_to_message(%{event_type: "user_message", content: c, run_id: run_id})
       when is_binary(c),
       do: [%{role: "user", content: c, run_id: run_id}]

  defp event_to_message(%{event_type: "completed", content: c, run_id: run_id})
       when is_binary(c),
       do: [%{role: "assistant", content: c, run_id: run_id}]

  defp event_to_message(%{event_type: "failed", content: c})
       when is_binary(c),
       do: [%{role: "system", content: c}]

  defp event_to_message(_), do: []

  # ── handle_params ────────────────────────────────────────────────────────

  @impl true
  def handle_params(%{"execution" => exec_id} = _params, _uri, socket) do
    if socket.assigns.selected_execution && socket.assigns.selected_execution.id == exec_id do
      {:noreply, socket}
    else
      org = socket.assigns.current_scope.organization

      case FlowExecutions.get_execution_for_org(org.id, exec_id) do
        nil ->
          {:noreply,
           push_patch(socket,
             to: ~p"/flows/#{socket.assigns.flow.id}/edit"
           )}

        execution ->
          sorted = (execution.node_executions || []) |> Enum.sort_by(& &1.inserted_at)
          execution = %{execution | node_executions: sorted}
          node_map = Enum.map(sorted, &node_execution_to_map/1)

          execution_io = %{
            input: execution.input,
            output: execution.output
          }

          merged_definition =
            ExecutionGraphMerger.merge(socket.assigns.flow.definition, node_map, execution_io)

          {:noreply,
           socket
           |> assign(
             selected_execution: execution,
             expanded_exec_node: nil,
             show_executions_drawer: true
           )
           |> push_event("load_execution_view", %{
             definition: merged_definition,
             nodes: node_map
           })}
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

  # ── Chat ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}
  end

  @impl true
  def handle_event("chat_input_change", params, socket) do
    message = get_in(params, ["message"]) || get_in(params, ["chat", "message"]) || ""
    {:noreply, assign(socket, chat_input: message)}
  end

  @impl true
  def handle_event("send_chat", params, socket) do
    message =
      (get_in(params, ["message"]) || get_in(params, ["chat", "message"]) || "")
      |> String.trim()

    cond do
      message == "" -> {:noreply, socket}
      socket.assigns.chat_loading -> {:noreply, socket}
      true -> dispatch_send_chat(socket, message)
    end
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    flow = socket.assigns.flow

    _ = FlowConversations.archive_active_conversation(flow.id)
    cancel_timer(socket.assigns[:chat_timeout_ref])

    {:noreply,
     assign(socket,
       chat_messages: [],
       chat_input: "",
       chat_loading: false,
       current_run_id: nil,
       current_stream: nil,
       chat_timeout_ref: nil
     )}
  end

  # ── Node selection ───────────────────────────────────────────────────────

  @impl true
  def handle_event("node_selected", %{"id" => id, "type" => type, "data" => data}, socket) do
    # Normalize Drawflow class back to canonical type
    type = if type == "df-exec-data-node", do: "exec_data", else: type

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
  def handle_event("open_run_drawer", _params, socket) do
    example = SampleInput.generate(socket.assigns.flow)
    run_input = if example == %{}, do: "{}", else: Jason.encode!(example, pretty: true)

    {:noreply,
     assign(socket,
       show_run_drawer: true,
       show_executions_drawer: false,
       run_error: nil,
       run_input: run_input
     )}
  end

  @impl true
  def handle_event("close_run_drawer", _params, socket) do
    {:noreply, assign(socket, show_run_drawer: false)}
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
         |> assign(running: true, run_error: nil, run_task_ref: task.ref)}

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
    {:noreply,
     push_patch(socket,
       to: ~p"/flows/#{socket.assigns.flow.id}/edit?execution=#{id}"
     )}
  end

  @impl true
  def handle_event("deselect_execution", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/flows/#{socket.assigns.flow.id}/edit"
     )}
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
      status: normalize_execution_status(ne),
      duration_ms: ne.duration_ms,
      input: ne.input,
      output: ne.output,
      error: ne.error
    }
  end

  # Normalizes status for nodes that were branch-skipped but persisted as
  # "completed" (pre-fix data). New executions already save "skipped" directly.
  defp normalize_execution_status(%{status: "skipped"}), do: "skipped"

  defp normalize_execution_status(%{output: %{"output" => "__branch_skipped__"}}),
    do: "skipped"

  defp normalize_execution_status(%{status: status}), do: status

  defp node_names(definition) do
    definition
    |> Map.get("nodes", [])
    |> Map.new(fn n -> {n["id"], get_in(n, ["data", "name"]) || n["id"]} end)
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

  # ── Flow Agent broadcasts ──────────────────────────────────────────────

  @impl true
  def handle_info({:run_started, %{run_id: run_id}}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{run_id}")
    end

    {:noreply,
     assign(socket,
       chat_loading: true,
       current_run_id: run_id,
       current_stream: "",
       chat_open: true
     )}
  end

  @impl true
  def handle_info({:definition_delta, %{delta: delta, run_id: run_id}}, socket) do
    # When chat_loading is true but current_run_id isn't yet set, the user's
    # run_started broadcast was delayed — still belongs to the active chat,
    # accept the delta and lock in the run_id now so completion can match.
    if chat_run_match?(socket, run_id) do
      next = (socket.assigns.current_stream || "") <> delta
      {:noreply, assign(socket, current_run_id: run_id, current_stream: next)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:run_completed, %{kind: :explain, run_id: run_id, answer: answer}},
        socket
      ) do
    if chat_run_match?(socket, run_id) do
      assistant_msg = %{role: "assistant", content: answer, run_id: run_id}
      cancel_timer(socket.assigns[:chat_timeout_ref])

      {:noreply,
       assign(socket,
         chat_loading: false,
         current_stream: nil,
         current_run_id: nil,
         chat_timeout_ref: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [assistant_msg])
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:run_completed, %{run_id: run_id, definition: definition, summary: summary}},
        socket
      )
      when is_map(definition) do
    if chat_run_match?(socket, run_id) do
      flow = %{socket.assigns.flow | definition: definition}
      assistant_msg = %{role: "assistant", content: summary, run_id: run_id}
      cancel_timer(socket.assigns[:chat_timeout_ref])

      {:noreply,
       socket
       |> assign(
         flow: flow,
         chat_loading: false,
         current_stream: nil,
         current_run_id: nil,
         chat_timeout_ref: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [assistant_msg])
       )
       |> push_event("flow_chat:reload_definition", %{definition: definition})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_failed, %{run_id: run_id, reason: reason}}, socket) do
    if chat_run_match?(socket, run_id) do
      system_msg = %{role: "system", content: reason}
      cancel_timer(socket.assigns[:chat_timeout_ref])

      {:noreply,
       socket
       |> assign(
         chat_loading: false,
         current_stream: nil,
         current_run_id: nil,
         chat_timeout_ref: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [system_msg])
       )
       |> put_flash(:error, "Agente falhou: #{reason}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:chat_timeout, socket) do
    if socket.assigns.chat_loading do
      {:noreply,
       socket
       |> assign(chat_loading: false, current_stream: nil, chat_timeout_ref: nil)
       |> put_flash(
         :error,
         "O agente não respondeu a tempo. Tente novamente."
       )}
    else
      {:noreply, socket}
    end
  end

  # ── Async Task Results ─────────────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, socket) when socket.assigns.run_task_ref == ref do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, %{execution_id: execution_id}} ->
        {:noreply,
         socket
         |> assign(running: false, run_task_ref: nil, show_run_drawer: false)
         |> push_patch(to: ~p"/flows/#{socket.assigns.flow.id}/edit?execution=#{execution_id}")}

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

  # ── Chat helpers ─────────────────────────────────────────────────────────

  defp dispatch_send_chat(socket, message) do
    case FlowAgent.start(socket.assigns.flow, socket.assigns.current_scope, message) do
      {:ok, _job} ->
        user_msg = %{role: "user", content: message, run_id: nil}
        timer = Process.send_after(self(), :chat_timeout, @chat_timeout_ms)

        {:noreply,
         socket
         |> assign(
           chat_loading: true,
           chat_input: "",
           chat_messages: cap_messages(socket.assigns.chat_messages ++ [user_msg]),
           chat_open: true,
           chat_timeout_ref: timer
         )}

      {:error, :empty_message} ->
        {:noreply, socket}

      {:error, :message_too_long} ->
        {:noreply, put_flash(socket, :error, "Mensagem muito longa (máx 10.000 caracteres).")}

      {:error, :definition_too_large} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "O fluxo atual é muito grande para edição pelo agente. Simplifique e tente novamente."
         )}

      {:error, :limit_exceeded} ->
        {:noreply, put_flash(socket, :error, "Limite do plano atingido para gerações de IA.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Não autorizado.")}

      {:error, reason} ->
        require Logger
        Logger.warning("FlowAgent.start failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Falha ao iniciar o agente. Tente novamente.")}
    end
  end

  defp cap_messages(messages) when length(messages) > @chat_message_cap do
    Enum.take(messages, -@chat_message_cap)
  end

  defp cap_messages(messages), do: messages

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  # Accept broadcasts both when current_run_id is known (normal path) and when
  # it is still nil but a chat is in flight (race where :run_started hasn't
  # been delivered yet). Rejects broadcasts that arrive when the LiveView
  # isn't loading anything.
  defp chat_run_match?(socket, run_id) do
    cond do
      socket.assigns.current_run_id == run_id -> true
      is_nil(socket.assigns.current_run_id) and socket.assigns.chat_loading -> true
      true -> false
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col overflow-hidden bg-background text-foreground">
      <.flow_header
        flow={@flow}
        saving={@saving}
        saved={@saved}
        chat_open={@chat_open}
      />

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
          node_names={node_names(@flow.definition)}
        />

        <%!-- Test Run drawer (right of canvas) --%>
        <.run_drawer
          show={@show_run_drawer}
          run_input={@run_input}
          running={@running}
          run_error={@run_error}
        />

        <%!-- Flow Agent chat drawer (right of canvas) --%>
        <.flow_chat_drawer
          show={@chat_open}
          messages={@chat_messages}
          input={@chat_input}
          loading={@chat_loading}
          current_stream={@current_stream}
        />
      </div>

      <.json_preview_modal :if={@show_json_modal} flow={@flow} json_preview={@json_preview} />

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
