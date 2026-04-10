defmodule BlackboexWeb.ApiLive.Edit.ChatLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.Components.Editor.FileTree
  import BlackboexWeb.Components.Editor.FileEditor

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.DiffEngine
  alias Blackboex.Conversations, as: AgentConversations
  alias BlackboexWeb.ApiLive.Edit.ChatLiveHelpers, as: H
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

        api = socket.assigns.api
        files = Apis.list_files_with_virtual(api)

        source_content =
          files |> Enum.filter(&(&1.file_type == "source")) |> Enum.map_join("\n\n", & &1.content)

        test_content =
          files |> Enum.filter(&(&1.file_type == "test")) |> Enum.map_join("\n\n", & &1.content)

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
            code: source_content,
            test_code: test_content,
            files: files,
            selected_file: Enum.find(files, &(&1.path == "/src/handler.ex")),
            editor_live_content: nil,
            confirm: nil
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
      <div class="flex h-full min-h-0">
        <%!-- File Tree (left) --%>
        <div class="w-48 shrink-0">
          <.file_tree
            files={@files}
            selected_path={if(@selected_file, do: @selected_file.path)}
            generating={@chat_loading}
          />
        </div>
        <%!-- Code Editor (center) --%>
        <div class="flex-1 min-w-0">
          <.file_editor
            file={@selected_file}
            live_content={@editor_live_content}
            streaming={@chat_loading}
            read_only={@selected_file && Map.get(@selected_file, :read_only, false)}
          />
        </div>
        <%!-- Chat Panel (right) --%>
        <div class="w-[420px] shrink-0 border-l">
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
        </div>
      </div>

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
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

  # ── Confirm Dialog ────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = H.build_confirm(params["action"], params)
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

  # ── File Tree Events ──────────────────────────────────────────────────

  def handle_event("select_file", %{"path" => path}, socket) do
    file = Enum.find(socket.assigns.files, &(&1.path == path))

    {:noreply,
     socket
     |> assign(selected_file: file)
     |> recompute_editor_content()}
  end

  def handle_event("copy_file", _params, socket) do
    content = socket.assigns.editor_live_content || get_selected_content(socket)
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: content})}
  end

  def handle_event("download_file", _params, socket) do
    content = socket.assigns.editor_live_content || get_selected_content(socket)
    filename = H.filename_from_path(socket.assigns.selected_file)
    {:noreply, push_event(socket, "download_file", %{content: content, filename: filename})}
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

    handler_file = Enum.find(socket.assigns.files, &(&1.path == "/src/handler.ex"))

    {:noreply,
     socket
     |> assign(
       current_run_id: run_id,
       current_run: run,
       chat_loading: true,
       pipeline_status: :generating,
       streaming_tokens: "",
       selected_file: handler_file || socket.assigns.selected_file
     )
     |> recompute_editor_content()
     |> push_patch(to: edit_tab_path(socket, "chat"))}
  end

  def handle_info({:agent_streaming, %{delta: delta} = payload}, socket) do
    if socket.assigns.current_run_id do
      socket = maybe_switch_file_for_streaming(socket, payload)
      {:noreply, apply_streaming_delta(socket, delta)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:agent_action, %{tool: tool_name, args: args}}, socket) do
    now = DateTime.utc_now()
    seq = length(socket.assigns.agent_events)
    normalized_args = H.normalize_tool_input(args)
    event = %{type: :tool_call, tool: tool_name, args: normalized_args, timestamp: now, id: seq}

    status = H.agent_tool_to_status(tool_name)

    socket =
      socket
      |> assign(
        pipeline_status: status,
        agent_events: socket.assigns.agent_events ++ [event],
        streaming_tokens: ""
      )
      |> auto_select_file_for_step(status)
      |> apply_action_to_editor(tool_name, args)
      |> recompute_editor_content()

    {:noreply, socket}
  end

  def handle_info({:agent_action, %{tool: tool_name}}, socket) do
    status = H.agent_tool_to_status(tool_name)

    {:noreply,
     socket
     |> assign(pipeline_status: status)
     |> auto_select_file_for_step(status)}
  end

  def handle_info({:tool_started, %{tool: tool_name}}, socket) do
    status = H.agent_tool_to_status(tool_name)

    {:noreply,
     socket
     |> assign(pipeline_status: status)
     |> auto_select_file_for_step(status)}
  end

  def handle_info({:step_started, %{step: step}}, socket) do
    status = H.pipeline_step_to_status(step)

    socket =
      if status in [:compiling, :formatting, :linting, :fixing] do
        refresh_files_from_db(socket)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(pipeline_status: status, streaming_tokens: "")
     |> auto_select_file_for_step(status)
     |> recompute_editor_content()}
  end

  def handle_info({:step_completed, %{step: step} = payload}, socket) do
    socket =
      if step in [:compiling, :formatting, :linting, :fixing_compilation, :fixing_lint] do
        refresh_files_from_db(socket)
      else
        socket
      end

    socket =
      socket
      |> assign(streaming_tokens: "")
      |> maybe_update_code_from_step(payload)
      |> recompute_editor_content()

    {:noreply, socket}
  end

  def handle_info({:step_failed, _payload}, socket) do
    {:noreply, assign(socket, streaming_tokens: "")}
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

    files = Apis.list_files(refreshed_api.id)
    selected_file = Enum.find(files, &(&1.path == "/src/handler.ex"))

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
        validation_report: H.restore_validation_report(refreshed_api.validation_report),
        test_summary: H.derive_test_summary(refreshed_api.validation_report),
        files: files,
        selected_file: selected_file
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

  def handle_info({:manifest_ready, %{manifest: manifest_files}}, socket)
      when is_list(manifest_files) do
    files = Apis.list_files(socket.assigns.api.id)

    {:noreply,
     assign(socket,
       files: files,
       pipeline_status: "Planning complete: #{length(manifest_files)} files"
     )}
  end

  def handle_info({:file_started, %{path: path}}, socket) do
    api = socket.assigns.api
    files = Apis.list_files(api.id)
    file = Enum.find(files, &(&1.path == path))

    {files, file} =
      if is_nil(file) do
        case Apis.create_file(api, %{
               path: path,
               content: "# Generating...\n",
               file_type: "source"
             }) do
          {:ok, new_file} ->
            updated_files = Apis.list_files(api.id)
            {updated_files, new_file}

          _ ->
            virtual = %{path: path, content: "# Generating...\n", file_type: "source"}
            {files, virtual}
        end
      else
        {files, file}
      end

    {:noreply,
     assign(socket,
       files: files,
       selected_file: file,
       streaming_tokens: "",
       editor_live_content: nil,
       pipeline_status: "Generating #{path}..."
     )}
  end

  def handle_info({:file_completed, %{path: path}}, socket) do
    socket = refresh_files_from_db(socket)
    file = Enum.find(socket.assigns.files, &(&1.path == path))

    {:noreply,
     assign(socket,
       selected_file: file || socket.assigns.selected_file,
       streaming_tokens: "",
       editor_live_content: nil,
       pipeline_status: "Completed #{path}"
     )}
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

  # ── Private Helpers (socket-dependent) ───────────────────────────────

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
          |> Enum.map(&H.event_to_display/1)
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
    api_id = socket.assigns.api.id
    files = Apis.list_files(api_id)
    selected_file = Enum.find(files, &(&1.path == "/src/handler.ex"))

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
       streaming_tokens: "",
       files: files,
       selected_file: selected_file
     )
     |> put_flash(:info, "Change applied")}
  end

  defp do_agent_chat(socket, message) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        scope = socket.assigns.current_scope

        case Blackboex.Agent.start_edit(api, message, scope.user.id) do
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

  defp handle_agent_code_completed(socket, code, test_code, summary, _api) do
    assistant_msg = %{"role" => "assistant", "content" => summary || "Code updated successfully"}
    completion_event = %{type: :message, role: "assistant", content: assistant_msg["content"]}
    socket = assign(socket, agent_events: socket.assigns.agent_events ++ [completion_event])

    has_previous_code = socket.assigns.code != ""

    if has_previous_code do
      files_changed = build_files_changed(socket.assigns.files, socket.assigns.api.id)
      code_diff = DiffEngine.compute_diff(socket.assigns.code, code)

      {:noreply,
       socket
       |> assign(
         pending_edit: %{
           code: code,
           test_code: test_code,
           diff: code_diff,
           test_diff: [],
           files_changed: files_changed,
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
       |> put_flash(:info, summary || "Code generated successfully")}
    end
  end

  defp build_files_changed(old_files, api_id) do
    new_files = Apis.list_files(api_id)

    new_files
    |> Enum.map(fn new_file ->
      old_file = Enum.find(old_files, &(&1.path == new_file.path))
      old_content = if old_file, do: old_file.content || "", else: ""
      new_content = new_file.content || ""

      %{
        path: new_file.path,
        content: new_content,
        diff: DiffEngine.compute_diff(old_content, new_content),
        changed: old_content != new_content
      }
    end)
    |> Enum.filter(& &1.changed)
  end

  defp maybe_update_code_from_step(socket, %{code: code}) when is_binary(code) do
    assign(socket, code: code)
  end

  defp maybe_update_code_from_step(socket, %{test_code: test_code}) when is_binary(test_code) do
    assign(socket, test_code: test_code)
  end

  defp maybe_update_code_from_step(socket, %{step: :generating_docs, content: doc})
       when is_binary(doc) do
    files =
      Enum.map(socket.assigns.files, fn
        %{path: "/README.md"} = f -> %{f | content: doc}
        f -> f
      end)

    assign(socket, files: files)
  end

  defp maybe_update_code_from_step(socket, _payload), do: socket

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

  defp apply_result_to_editor(socket, "generate_tests", true, content) when is_binary(content) do
    assign(socket, test_code: content)
  end

  defp apply_result_to_editor(socket, _tool, _success, _content), do: socket

  defp recompute_editor_content(socket) do
    a = socket.assigns
    content = resolve_editor_content(a)
    assign(socket, editor_live_content: content)
  end

  defp resolve_editor_content(%{chat_loading: false}), do: nil

  defp resolve_editor_content(assigns) do
    path = assigns.selected_file && assigns.selected_file.path
    target = H.streaming_target(assigns.pipeline_status, path)
    resolve_for_target(target, assigns)
  end

  defp resolve_for_target(target, assigns)
       when target in [:streaming_source, :streaming_test, :streaming_doc] do
    if assigns.streaming_tokens != "" do
      H.strip_code_fences(assigns.streaming_tokens)
    else
      static_content_for(target, assigns)
    end
  end

  defp resolve_for_target(:source, assigns), do: assigns.code
  defp resolve_for_target(:test, assigns), do: assigns.test_code
  defp resolve_for_target(:doc, assigns), do: selected_file_content(assigns)
  defp resolve_for_target(_, _assigns), do: nil

  defp static_content_for(:streaming_source, assigns), do: assigns.code
  defp static_content_for(:streaming_test, assigns), do: assigns.test_code
  defp static_content_for(:streaming_doc, assigns), do: selected_file_content(assigns)

  defp selected_file_content(assigns),
    do: (assigns.selected_file && assigns.selected_file.content) || ""

  defp refresh_files_from_db(socket) do
    api = Blackboex.Repo.reload!(socket.assigns.api)
    files = Apis.list_files_with_virtual(api)
    current_path = socket.assigns.selected_file && socket.assigns.selected_file.path
    selected = Enum.find(files, &(&1.path == current_path))
    handler = Enum.find(files, &(&1.path == "/src/handler.ex"))
    test_file = Enum.find(files, &(&1.path == "/test/handler_test.ex"))

    assign(socket,
      api: api,
      files: files,
      selected_file: selected || socket.assigns.selected_file,
      code: (handler && handler.content) || socket.assigns.code,
      test_code: (test_file && test_file.content) || socket.assigns.test_code
    )
  end

  defp auto_select_file_for_step(socket, status)
       when status in [:generating, :compiling, :formatting, :linting] do
    file = Enum.find(socket.assigns.files, &(&1.path == "/src/handler.ex"))
    if file, do: assign(socket, selected_file: file), else: socket
  end

  defp auto_select_file_for_step(socket, status)
       when status in [:generating_tests, :running_tests] do
    file = Enum.find(socket.assigns.files, &(&1.path == "/test/handler_test.ex"))
    if file, do: assign(socket, selected_file: file), else: socket
  end

  defp auto_select_file_for_step(socket, :generating_docs) do
    file = Enum.find(socket.assigns.files, &(&1.path == "/README.md"))
    if file, do: assign(socket, selected_file: file), else: socket
  end

  defp auto_select_file_for_step(socket, _status), do: socket

  defp maybe_switch_file_for_streaming(socket, payload) do
    streaming_path = Map.get(payload, :path)
    selected_path = socket.assigns.selected_file && socket.assigns.selected_file.path

    if is_nil(streaming_path) or streaming_path == selected_path do
      socket
    else
      files = socket.assigns.files
      file = Enum.find(files, &(&1.path == streaming_path))

      if file do
        assign(socket,
          selected_file: file,
          streaming_tokens: "",
          editor_live_content: nil
        )
      else
        socket
      end
    end
  end

  defp apply_streaming_delta(socket, delta) do
    new_tokens = socket.assigns.streaming_tokens <> delta
    socket = assign(socket, streaming_tokens: new_tokens)

    if socket.assigns.pipeline_status == :fixing do
      socket
    else
      assign(socket, editor_live_content: H.strip_code_fences(new_tokens))
    end
  end

  defp edit_tab_path(socket, tab) do
    "/apis/#{socket.assigns.api.id}/edit/#{tab}"
  end

  defp get_selected_content(socket) do
    case socket.assigns.selected_file do
      %{content: content} when is_binary(content) -> content
      _ -> ""
    end
  end
end
