defmodule BlackboexWeb.ApiLive.Edit.ChatLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Billing.Enforcement
  alias Blackboex.Conversations, as: AgentConversations
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        api_id = socket.assigns.api.id
        {agent_conversation, active_run_id} = resolve_agent_state(api_id)

        Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api_id}")

        {agent_events, current_run} = load_conversation_events(agent_conversation)

        socket =
          assign(socket,
            chat_input: "",
            chat_loading: active_run_id != nil,
            pending_edit: nil,
            streaming_tokens: "",
            pipeline_status: nil,
            pre_edit_code: nil,
            current_run_id: active_run_id,
            current_run: current_run,
            agent_events: agent_events,
            agent_conversation: agent_conversation,
            code: socket.assigns.api.source_code || "",
            test_code: socket.assigns.api.test_code || ""
          )

        {:ok, socket}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="chat">
      <.live_component
        module={BlackboexWeb.Components.Editor.ChatPanel}
        id="chat-panel"
        events={@agent_events}
        input={@chat_input}
        loading={@chat_loading or @generation_status in ["pending", "generating", "validating"]}
        api_id={@api.id}
        pending_edit={@pending_edit}
        template_type={@api.template_type}
        streaming_tokens={if(@chat_loading, do: @streaming_tokens, else: "")}
        run={@current_run}
        pipeline_status={@pipeline_status}
      />
    </.editor_shell>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ── Command Palette Delegation ────────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── Tab-Specific Events ───────────────────────────────────────────────

  def handle_event("send_chat", %{"chat_input" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("send_chat", %{"chat_input" => message}, socket) do
    if socket.assigns.chat_loading do
      {:noreply, socket}
    else
      do_agent_chat(socket, message)
    end
  end

  def handle_event("accept_edit", _params, socket) do
    case socket.assigns.pending_edit do
      nil ->
        {:noreply, socket}

      %{code: proposed_code, test_code: proposed_test_code, instruction: instruction} ->
        do_accept_edit(socket, proposed_code, proposed_test_code, instruction)
    end
  end

  def handle_event("reject_edit", _params, socket) do
    {:noreply, assign(socket, pending_edit: nil)}
  end

  def handle_event("quick_action", %{"text" => text}, socket) do
    {:noreply, assign(socket, chat_input: text)}
  end

  def handle_event("clear_conversation", _params, socket) do
    if socket.assigns.chat_loading do
      {:noreply, put_flash(socket, :error, "Cannot clear while agent is running")}
    else
      {:noreply,
       assign(socket,
         pending_edit: nil,
         agent_events: [],
         streaming_tokens: ""
       )}
    end
  end

  def handle_event("cancel_pipeline", _params, socket) do
    socket =
      if previous = socket.assigns[:pre_edit_code] do
        socket
        |> assign(code: previous, pre_edit_code: nil)
        |> push_editor_value(previous)
        |> put_flash(:info, "Edit cancelled, code reverted")
      else
        socket
      end

    {:noreply,
     assign(socket,
       pipeline_status: nil,
       chat_loading: false,
       streaming_tokens: ""
     )}
  end

  # ── Agent Pipeline handle_info ────────────────────────────────────────

  @impl true
  def handle_info({:agent_run_started, %{run_id: run_id, run_type: _type}}, socket) do
    if old_run = socket.assigns.current_run_id do
      Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{old_run}")
    end

    Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")
    run = AgentConversations.get_run(run_id)

    {:noreply,
     socket
     |> assign(current_run_id: run_id, current_run: run, chat_loading: true)
     |> push_patch(to: edit_tab_path(socket, "chat"))}
  end

  def handle_info({:agent_streaming, %{delta: delta}}, socket) do
    if socket.assigns.current_run_id do
      new_tokens = socket.assigns.streaming_tokens <> delta
      {:noreply, assign(socket, streaming_tokens: new_tokens)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:agent_action, %{tool: tool_name, args: args}}, socket) do
    now = DateTime.utc_now()
    seq = length(socket.assigns.agent_events)
    normalized_args = normalize_tool_input(args)
    event = %{type: :tool_call, tool: tool_name, args: normalized_args, timestamp: now, id: seq}

    socket =
      socket
      |> assign(
        pipeline_status: agent_tool_to_status(tool_name),
        agent_events: socket.assigns.agent_events ++ [event],
        streaming_tokens: ""
      )
      |> apply_action_to_editor(tool_name, args)

    {:noreply, socket}
  end

  def handle_info({:agent_action, %{tool: tool_name}}, socket) do
    {:noreply, assign(socket, pipeline_status: agent_tool_to_status(tool_name))}
  end

  def handle_info({:tool_started, %{tool: tool_name}}, socket) do
    {:noreply, assign(socket, pipeline_status: agent_tool_to_status(tool_name))}
  end

  def handle_info({:tool_result, %{tool: tool_name, success: success} = payload}, socket) do
    content = Map.get(payload, :content, "")
    now = DateTime.utc_now()
    seq = length(socket.assigns.agent_events)

    event = %{
      type: :tool_result,
      tool: tool_name,
      success: success,
      content: content,
      timestamp: now,
      id: seq
    }

    socket =
      socket
      |> assign(agent_events: socket.assigns.agent_events ++ [event])
      |> apply_result_to_editor(tool_name, success, content)

    {:noreply, socket}
  end

  def handle_info({:guardrail_triggered, %{type: type}}, socket) do
    {:noreply, put_flash(socket, :error, "Agent limit reached: #{type}")}
  end

  def handle_info(
        {:agent_completed, %{code: code, test_code: test_code, summary: summary, run_id: run_id}},
        socket
      ) do
    Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{run_id}")

    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    refreshed_api = api || socket.assigns.api

    completed_run =
      case AgentConversations.get_run(run_id) do
        nil -> socket.assigns.current_run
        run -> run
      end

    socket =
      socket
      |> assign(
        api: refreshed_api,
        chat_loading: false,
        current_run_id: nil,
        current_run: completed_run,
        streaming_tokens: "",
        pipeline_status: nil,
        generation_status: refreshed_api.generation_status,
        versions: Apis.list_versions(refreshed_api.id),
        validation_report: restore_validation_report(refreshed_api.validation_report),
        test_summary: derive_test_summary(refreshed_api.validation_report)
      )

    effective_code = code || socket.assigns.code
    effective_test_code = test_code || socket.assigns.test_code

    if effective_code != "" and effective_code != nil do
      handle_agent_code_completed(
        socket,
        effective_code,
        effective_test_code,
        summary,
        refreshed_api
      )
    else
      {:noreply, put_flash(socket, :info, summary || "Agent completed")}
    end
  end

  def handle_info({:agent_failed, %{error: error, run_id: run_id}}, socket) do
    Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{run_id}")

    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    refreshed_api = api || socket.assigns.api

    failed_run =
      case AgentConversations.get_run(run_id) do
        nil -> socket.assigns.current_run
        run -> run
      end

    {:noreply,
     socket
     |> assign(
       api: refreshed_api,
       chat_loading: false,
       current_run_id: nil,
       current_run: failed_run,
       pipeline_status: nil,
       streaming_tokens: "",
       generation_status: refreshed_api.generation_status
     )
     |> put_flash(:error, "Agent failed: #{error}")}
  end

  def handle_info({:agent_message, %{role: "assistant", content: content}}, socket) do
    seq = length(socket.assigns.agent_events)

    event = %{
      type: :message,
      role: "assistant",
      content: content,
      timestamp: DateTime.utc_now(),
      id: seq
    }

    {:noreply, assign(socket, agent_events: socket.assigns.agent_events ++ [event])}
  end

  def handle_info({:agent_message, _payload}, socket), do: {:noreply, socket}
  def handle_info({:agent_started, _payload}, socket), do: {:noreply, socket}

  # ── Private Helpers ───────────────────────────────────────────────────

  defp shared_shell_assigns(assigns) do
    Map.take(assigns, [
      :api,
      :versions,
      :selected_version,
      :generation_status,
      :validation_report,
      :test_summary,
      :command_palette_open,
      :command_palette_query,
      :command_palette_selected
    ])
  end

  defp resolve_agent_state(api_id) do
    case AgentConversations.get_conversation_by_api(api_id) do
      nil -> {nil, nil}
      conv -> find_active_run(conv)
    end
  end

  defp load_conversation_events(nil), do: {[], nil}

  defp load_conversation_events(agent_conversation) do
    case AgentConversations.list_runs(agent_conversation.id, limit: 1) do
      [latest_run | _] ->
        events =
          AgentConversations.list_events(latest_run.id)
          |> Enum.map(&event_to_display/1)
          |> Enum.reject(&is_nil/1)

        {events, latest_run}

      [] ->
        {[], nil}
    end
  end

  defp find_active_run(conv) do
    active_run =
      AgentConversations.list_runs(conv.id, limit: 1)
      |> Enum.find(&(&1.status == "running"))

    if active_run,
      do: Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{active_run.id}")

    {conv, active_run && active_run.id}
  end

  defp do_accept_edit(socket, proposed_code, proposed_test_code, _instruction) do
    previous_code = socket.assigns.code
    test_code = proposed_test_code || socket.assigns.test_code

    {:noreply,
     socket
     |> assign(
       code: proposed_code,
       test_code: test_code,
       pending_edit: nil,
       pre_edit_code: previous_code,
       chat_loading: false,
       pipeline_status: nil,
       current_run_id: nil,
       streaming_tokens: ""
     )
     |> push_editor_value(proposed_code)
     |> put_flash(:info, "Change applied")}
  end

  defp do_agent_chat(socket, message) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        scope = socket.assigns.current_scope

        case Apis.start_agent_edit(api, message, scope.user.id) do
          {:ok, _api_id} ->
            user_msg = %{"role" => "user", "content" => message}

            {:noreply,
             socket
             |> assign(
               chat_loading: true,
               chat_input: "",
               streaming_tokens: "",
               agent_events:
                 socket.assigns.agent_events ++
                   [
                     %{
                       type: :message,
                       role: "user",
                       content: user_msg["content"],
                       timestamp: DateTime.utc_now(),
                       id: length(socket.assigns.agent_events)
                     }
                   ]
             )}

          {:error, reason} ->
            Logger.warning("Failed to start agent edit: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Failed to start agent")}
        end

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  defp event_to_display(%{event_type: "user_message"} = e) do
    %{type: :message, role: "user", content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  defp event_to_display(%{event_type: "assistant_message"} = e) do
    %{
      type: :message,
      role: "assistant",
      content: e.content,
      timestamp: e.inserted_at,
      id: e.sequence
    }
  end

  defp event_to_display(%{event_type: "tool_call"} = e) do
    args = normalize_tool_input(e.tool_input)

    %{
      type: :tool_call,
      tool: e.tool_name,
      args: args,
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  defp event_to_display(%{event_type: "tool_result"} = e) do
    %{
      type: :tool_result,
      tool: e.tool_name,
      success: e.tool_success,
      content: e.content || "",
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  defp event_to_display(%{event_type: "status_change"} = e) do
    %{type: :status, content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  defp event_to_display(_), do: nil

  defp normalize_tool_input(nil), do: %{}

  defp normalize_tool_input(args) when is_map(args),
    do: Map.new(args, fn {k, v} -> {to_string(k), v} end)

  defp normalize_tool_input(_), do: %{}

  defp agent_tool_to_status("generate_code"), do: :generating
  defp agent_tool_to_status("compile_code"), do: :compiling
  defp agent_tool_to_status("format_code"), do: :formatting
  defp agent_tool_to_status("lint_code"), do: :linting
  defp agent_tool_to_status("generate_tests"), do: :generating_tests
  defp agent_tool_to_status("run_tests"), do: :running_tests
  defp agent_tool_to_status("generate_docs"), do: :generating_docs
  defp agent_tool_to_status("submit_code"), do: :submitting
  defp agent_tool_to_status(_), do: :processing

  defp handle_agent_code_completed(socket, code, test_code, summary, api) do
    assistant_msg = %{"role" => "assistant", "content" => summary || "Code updated successfully"}
    completion_event = %{type: :message, role: "assistant", content: assistant_msg["content"]}
    socket = assign(socket, agent_events: socket.assigns.agent_events ++ [completion_event])

    has_previous_code = (api.source_code || "") != ""

    if has_previous_code do
      code_diff = DiffEngine.compute_diff(socket.assigns.code, code)

      {:noreply,
       socket
       |> assign(
         pending_edit: %{
           code: code,
           test_code: test_code,
           diff: code_diff,
           test_diff: [],
           explanation: summary || "Agent completed",
           instruction: summary,
           validation: nil
         }
       )
       |> put_flash(:info, summary || "Code ready for review")}
    else
      test_code = test_code || ""

      {:noreply,
       socket
       |> assign(code: code, test_code: test_code)
       |> push_editor_value(code)
       |> put_flash(:info, summary || "Code generated successfully")}
    end
  end

  defp apply_action_to_editor(socket, "compile_code", %{"code" => code}) do
    assign(socket, code: code)
  end

  defp apply_action_to_editor(socket, "run_tests", %{"code" => code, "test_code" => test_code}) do
    assign(socket, code: code, test_code: test_code)
  end

  defp apply_action_to_editor(socket, "submit_code", %{"code" => code} = args) do
    test_code = Map.get(args, "test_code", socket.assigns.test_code)
    assign(socket, code: code, test_code: test_code)
  end

  defp apply_action_to_editor(socket, _tool, _args), do: socket

  defp apply_result_to_editor(socket, "format_code", true, content) when is_binary(content) do
    assign(socket, code: content)
  end

  defp apply_result_to_editor(socket, "generate_tests", true, content) when is_binary(content) do
    assign(socket, test_code: content)
  end

  defp apply_result_to_editor(socket, _tool, _success, _content), do: socket

  defp push_editor_value(socket, code) do
    editor_path = "api_#{socket.assigns.api.id}.ex"
    LiveMonacoEditor.set_value(socket, code, to: editor_path)
  end

  defp edit_tab_path(socket, tab) do
    "/apis/#{socket.assigns.api.id}/edit/#{tab}"
  end

  defp restore_validation_report(nil), do: nil

  defp restore_validation_report(report) when is_map(report) do
    %{
      compilation: safe_to_atom(report["compilation"]),
      compilation_errors: report["compilation_errors"] || [],
      format: safe_to_atom(report["format"]),
      format_issues: report["format_issues"] || [],
      credo: safe_to_atom(report["credo"]),
      credo_issues: report["credo_issues"] || [],
      tests: safe_to_atom(report["tests"]),
      test_results: report["test_results"] || [],
      overall: safe_to_atom(report["overall"])
    }
  end

  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass

  defp derive_test_summary(nil), do: nil

  defp derive_test_summary(report) when is_map(report) do
    test_results = report["test_results"] || []

    if test_results != [] do
      passed =
        Enum.count(test_results, fn item -> (item[:status] || item["status"]) == "passed" end)

      total = length(test_results)
      "#{passed}/#{total}"
    else
      nil
    end
  end
end
