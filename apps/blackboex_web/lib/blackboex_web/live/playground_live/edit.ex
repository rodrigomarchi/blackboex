defmodule BlackboexWeb.PlaygroundLive.Edit do
  @moduledoc """
  Single-cell code editor and REPL for Playgrounds.
  Executes Elixir code in a sandboxed environment with execution history.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Editor.ExecutionHistory
  import BlackboexWeb.Components.Editor.PageHeader
  import BlackboexWeb.Components.Editor.PlaygroundChatPanel
  import BlackboexWeb.Components.Editor.TerminalOutput
  import BlackboexWeb.Components.Shared.PlaygroundEditorField
  import BlackboexWeb.Components.Shared.UnderlineTabs

  alias Blackboex.PlaygroundAgent
  alias Blackboex.PlaygroundConversations
  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Completer
  alias Blackboex.Policy

  @impl true
  def mount(%{"playground_slug" => slug}, _session, socket) do
    project = socket.assigns.current_scope.project

    case Playgrounds.get_playground_by_slug(project.id, slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Playground not found")
         |> push_navigate(to: project_path(socket.assigns.current_scope, "/playgrounds"))}

      playground ->
        executions = Playgrounds.list_executions(playground.id)
        {selected, selected_id} = select_latest(executions)
        chat_messages = load_chat_messages(playground.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Blackboex.PubSub,
            "playground_agent:playground:#{playground.id}"
          )
        end

        {:ok,
         assign(socket,
           playground: playground,
           form: to_form(Playgrounds.change_playground(playground)),
           page_title: playground.name,
           output: playground.last_output,
           running: false,
           executions: executions,
           selected_execution_id: selected_id,
           selected_execution: selected,
           confirm: nil,
           active_bottom_tab: "output",
           chat_messages: chat_messages,
           chat_input: "",
           chat_loading: false,
           chat_slow_timer: nil,
           current_run_id: nil,
           current_stream: nil
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ── Code Events ───────────────────────────────────────────

  @impl true
  def handle_event("update_code", %{"value" => code}, socket) do
    {:noreply, assign(socket, current_code: code)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    code = socket.assigns[:current_code] || socket.assigns.playground.code
    playground = socket.assigns.playground

    case Playgrounds.create_execution(playground, code) do
      {:ok, execution} ->
        start_async_execution(playground, code, execution.id)
        executions = [execution | socket.assigns.executions]

        {:noreply,
         assign(socket,
           running: true,
           executions: executions,
           selected_execution_id: execution.id,
           selected_execution: execution
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to start execution")}
    end
  end

  @impl true
  def handle_event("save_code", _params, socket) do
    code = socket.assigns[:current_code] || socket.assigns.playground.code

    case Playgrounds.update_playground(socket.assigns.playground, %{code: code}) do
      {:ok, playground} ->
        {:noreply,
         socket
         |> assign(playground: playground)
         |> put_flash(:info, "Saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  @impl true
  def handle_event("save", %{"playground" => params}, socket) do
    case Playgrounds.update_playground(socket.assigns.playground, params) do
      {:ok, playground} ->
        {:noreply,
         socket
         |> assign(
           playground: playground,
           form: to_form(Playgrounds.change_playground(playground))
         )
         |> put_flash(:info, "Saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("autocomplete", %{"hint" => hint}, socket) do
    items = Completer.complete(hint)
    {:reply, %{items: items}, socket}
  end

  @impl true
  def handle_event("format_code", _params, socket) do
    code = socket.assigns[:current_code] || socket.assigns.playground.code || ""

    case format_elixir_code(code) do
      {:ok, formatted} ->
        {:noreply, push_event(socket, "formatted_code", %{code: formatted})}

      {:error, msg} ->
        {:noreply, put_flash(socket, :error, "Format error: #{msg}")}
    end
  end

  # ── Navigation Events ────────────────────────────────────

  @impl true
  def handle_event("select_playground", %{"slug" => slug}, socket) do
    scope = socket.assigns.current_scope
    path = project_path(scope, "/playgrounds/#{slug}/edit")
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("new_playground", _params, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    user = scope.user

    attrs = %{
      name: "Untitled",
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user.id
    }

    case Playgrounds.create_playground(attrs) do
      {:ok, pg} ->
        path = project_path(scope, "/playgrounds/#{pg.slug}/edit")
        {:noreply, push_navigate(socket, to: path)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create playground")}
    end
  end

  @impl true
  def handle_event("validate", %{"playground" => params}, socket) do
    changeset =
      socket.assigns.playground
      |> Playgrounds.Playground.update_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  # ── Confirm Dialog ────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", %{"action" => "delete"} = params, socket) do
    name = params["name"] || "this playground"

    confirm = %{
      title: "Delete playground?",
      description:
        "\"#{name}\" and its execution history will be permanently removed. This action cannot be undone.",
      variant: :danger,
      confirm_label: "Delete",
      event: "delete",
      meta: Map.take(params, ["id", "slug"])
    }

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
      %{event: event, meta: meta} -> handle_event(event, meta, assign(socket, confirm: nil))
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id} = params, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:playground_delete, scope, org),
         pg when not is_nil(pg) <- Playgrounds.get_playground(project.id, id),
         {:ok, _} <- Playgrounds.delete_playground(pg) do
      if pg.id == socket.assigns.playground.id do
        {:noreply,
         socket
         |> put_flash(:info, "Playground deleted.")
         |> push_navigate(to: project_path(scope, "/playgrounds"))}
      else
        {:noreply,
         put_flash(socket, :info, "Playground \"#{params["slug"] || pg.slug}\" deleted.")}
      end
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized to delete this playground.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Playground not found.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete playground.")}
    end
  end

  # ── Execution History Events ──────────────────────────────

  @impl true
  def handle_event("select_execution", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.executions, &(&1.id == id))

    {:noreply,
     assign(socket,
       selected_execution_id: id,
       selected_execution: selected
     )}
  end

  # ── Chat (AI Agent) Events ─────────────────────────────────

  @impl true
  def handle_event("switch_bottom_tab", %{"tab" => tab}, socket) when tab in ["output", "chat"] do
    {:noreply, assign(socket, active_bottom_tab: tab)}
  end

  @impl true
  def handle_event("chat_input_change", %{"message" => value}, socket) do
    {:noreply, assign(socket, chat_input: value)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    if socket.assigns.chat_loading do
      {:noreply,
       put_flash(socket, :error, "Aguarde a resposta do agente antes de iniciar um novo chat.")}
    else
      pg = socket.assigns.playground

      case PlaygroundConversations.start_new_conversation(
             pg.id,
             pg.organization_id,
             pg.project_id
           ) do
        {:ok, _new_conv} ->
          {:noreply,
           socket
           |> assign(chat_messages: [], chat_input: "", current_stream: nil, current_run_id: nil)
           |> put_flash(:info, "Novo chat iniciado.")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Não foi possível iniciar novo chat: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("send_chat", %{"message" => message}, socket) do
    message = String.trim(message)
    playground = socket.assigns.playground
    scope = socket.assigns.current_scope

    cond do
      message == "" ->
        {:noreply, socket}

      socket.assigns.chat_loading ->
        {:noreply, socket}

      true ->
        current_code = socket.assigns[:current_code]
        playground = ensure_code_synced(playground, current_code)

        case PlaygroundAgent.start(playground, scope, message) do
          {:ok, _job} ->
            user_msg = %{role: "user", content: message}
            slow_timer = Process.send_after(self(), :chat_slow_warning, 30_000)

            {:noreply,
             socket
             |> assign(
               playground: playground,
               chat_input: "",
               chat_loading: true,
               chat_slow_timer: slow_timer,
               chat_messages: socket.assigns.chat_messages ++ [user_msg],
               active_bottom_tab: "chat"
             )}

          {:error, :empty_message} ->
            {:noreply, socket}

          {:error, :limit_exceeded} ->
            {:noreply, put_flash(socket, :error, "Limite de gerações do plano atingido.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Falha ao iniciar agente: #{inspect(reason)}")}
        end
    end
  end

  # ── Async Results ─────────────────────────────────────────

  @impl true
  def handle_info({:execution_result, execution_id, result, duration_ms}, socket) do
    {output, status} =
      case result do
        {:ok, output} -> {output, "success"}
        {:error, reason} -> {"Error: #{reason}", "error"}
      end

    execution = Enum.find(socket.assigns.executions, &(&1.id == execution_id))

    case Playgrounds.complete_execution(execution, output, status, duration_ms) do
      {:ok, completed} ->
        # Also update playground.last_output for backward compat
        {:ok, playground} =
          Playgrounds.update_playground(socket.assigns.playground, %{
            code: completed.code_snapshot,
            last_output: output
          })

        executions =
          Enum.map(socket.assigns.executions, fn
            ex when ex.id == execution_id -> completed
            ex -> ex
          end)

        selected =
          if socket.assigns.selected_execution_id == execution_id,
            do: completed,
            else: socket.assigns.selected_execution

        Playgrounds.cleanup_old_executions(playground.id)

        {:noreply,
         assign(socket,
           running: false,
           executions: executions,
           selected_execution: selected,
           output: output,
           playground: playground
         )}

      {:error, _} ->
        {:noreply, assign(socket, running: false)}
    end
  end

  # ── AI Agent PubSub ───────────────────────────────────────

  @impl true
  def handle_info({:run_started, %{run_id: run_id}}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "playground_agent:run:#{run_id}")
    end

    {:noreply,
     assign(socket,
       chat_loading: true,
       current_run_id: run_id,
       current_stream: "",
       active_bottom_tab: "chat"
     )}
  end

  @impl true
  def handle_info({:code_delta, %{delta: delta, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      {:noreply, assign(socket, current_stream: (socket.assigns.current_stream || "") <> delta)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_completed, %{code: code, summary: summary, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      cancel_chat_slow_timer(socket)
      project = socket.assigns.current_scope.project
      playground = Playgrounds.get_playground(project.id, socket.assigns.playground.id)
      assistant_msg = %{role: "assistant", content: summary, run_id: run_id}

      {:noreply,
       socket
       |> assign(
         playground: playground,
         chat_loading: false,
         chat_slow_timer: nil,
         current_run_id: nil,
         current_stream: nil,
         chat_messages: socket.assigns.chat_messages ++ [assistant_msg]
       )
       |> push_event("playground_editor:set_value", %{code: code})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_failed, %{reason: reason, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      cancel_chat_slow_timer(socket)
      failure_msg = %{role: "system", content: "Agente falhou: #{reason}"}

      {:noreply,
       socket
       |> assign(
         chat_loading: false,
         chat_slow_timer: nil,
         current_run_id: nil,
         current_stream: nil,
         chat_messages: socket.assigns.chat_messages ++ [failure_msg]
       )
       |> put_flash(:error, "Agente falhou: #{reason}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:chat_slow_warning, socket) do
    if socket.assigns.chat_loading do
      warning = %{
        role: "system",
        content: "Agente está demorando mais que o esperado... aguarde (timeout: 3 min)."
      }

      {:noreply,
       assign(socket,
         chat_slow_timer: nil,
         chat_messages: socket.assigns.chat_messages ++ [warning]
       )}
    else
      {:noreply, assign(socket, chat_slow_timer: nil)}
    end
  end

  # ── Helpers ───────────────────────────────────────────────

  defp load_chat_messages(playground_id) do
    playground_id
    |> PlaygroundConversations.list_active_conversation_events(limit: 200)
    |> Enum.flat_map(&event_to_message/1)
  end

  defp event_to_message(%{event_type: "user_message", content: content}),
    do: [%{role: "user", content: content}]

  defp event_to_message(%{event_type: "completed", content: content, run_id: run_id}),
    do: [%{role: "assistant", content: content || "", run_id: run_id}]

  defp event_to_message(%{event_type: "failed", content: content}),
    do: [%{role: "system", content: "Agente falhou: #{content}"}]

  defp event_to_message(_), do: []

  defp cancel_chat_slow_timer(socket) do
    case socket.assigns[:chat_slow_timer] do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end

  defp ensure_code_synced(playground, nil), do: playground

  defp ensure_code_synced(playground, code) when is_binary(code) do
    if code == playground.code do
      playground
    else
      case Playgrounds.update_playground(playground, %{code: code}) do
        {:ok, updated} -> updated
        {:error, _} -> playground
      end
    end
  end

  defp start_async_execution(playground, code, execution_id) do
    self_pid = self()

    Task.start(fn ->
      {duration_us, result} =
        :timer.tc(fn -> Playgrounds.execute_code_raw(playground, code) end)

      send(self_pid, {:execution_result, execution_id, result, div(duration_us, 1000)})
    end)
  end

  defp format_elixir_code(code) do
    {:ok, code |> Code.format_string!() |> IO.iodata_to_binary()}
  rescue
    e in [SyntaxError, TokenMissingError] -> {:error, Exception.message(e)}
  end

  defp select_latest([latest | _]), do: {latest, latest.id}
  defp select_latest([]), do: {nil, nil}

  # ── Render ────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id="playground-panels" class="flex h-full w-full overflow-hidden" phx-hook="ResizablePanels">
      <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
        <.editor_page_header
          title={@playground.name}
          back_path={project_path(@current_scope, "/playgrounds")}
          back_label="Playgrounds"
        >
          <:actions>
            <.button variant="outline" size="sm" phx-click="save_code">
              <.icon name="hero-arrow-down-tray" class="size-4 mr-1" /> Save
            </.button>
            <.button
              variant="default"
              phx-click="run"
              disabled={@running}
            >
              <.icon
                name={if @running, do: "hero-arrow-path", else: "hero-play"}
                class={["size-4 mr-1", if(@running, do: "animate-spin")]}
              />
              {if @running, do: "Running...", else: "Run"}
            </.button>
          </:actions>
        </.editor_page_header>

        <div class="flex flex-1 min-h-0">
          <%!-- Editor + Output vertical stack --%>
          <div class="flex-1 flex flex-col min-w-0">
            <%!-- Code editor --%>
            <div class="flex-1 min-h-0 border-b">
              <.playground_editor_field
                id="playground-code-editor"
                value={@playground.code || ""}
                max_height="max-h-full"
                height="100%"
              />
            </div>

            <%!-- Vertical resize handle --%>
            <div
              data-resize-handle
              data-resize-direction="vertical"
              data-resize-target="output-pane"
              data-resize-css-var="--playground-output-pane-height"
              class="h-1 shrink-0 bg-border hover:bg-primary/50 transition-colors cursor-row-resize"
            />

            <%!-- Output / Chat tabs --%>
            <div
              id="output-pane"
              class="shrink-0 overflow-hidden flex flex-col"
              style="height: var(--playground-output-pane-height, 320px);"
            >
              <div class="shrink-0 bg-zinc-800 border-b border-zinc-700">
                <.underline_tabs
                  tabs={[{"output", "Output"}, {"chat", "Chat"}]}
                  active={@active_bottom_tab}
                  click_event="switch_bottom_tab"
                  class="border-b-0"
                />
              </div>

              <div :if={@active_bottom_tab == "output"} class="flex-1 overflow-hidden">
                <.terminal_output
                  output={if @selected_execution, do: @selected_execution.output}
                  status={if @selected_execution, do: @selected_execution.status}
                  duration_ms={if @selected_execution, do: @selected_execution.duration_ms}
                  run_number={if @selected_execution, do: @selected_execution.run_number}
                />
              </div>

              <div :if={@active_bottom_tab == "chat"} class="flex-1 overflow-hidden">
                <.playground_chat_panel
                  messages={@chat_messages}
                  input={@chat_input}
                  loading={@chat_loading}
                  current_stream={@current_stream}
                />
              </div>
            </div>
          </div>

          <%!-- Horizontal resize handle --%>
          <div
            data-resize-handle
            data-resize-direction="horizontal"
            data-resize-target="history-sidebar"
            data-resize-css-var="--playground-history-sidebar-width"
            class="w-1 shrink-0 bg-border hover:bg-primary/50 transition-colors cursor-col-resize hidden md:block"
          />

          <%!-- Right sidebar: execution history --%>
          <div
            id="history-sidebar"
            class="shrink-0 overflow-hidden hidden md:block"
            style="width: var(--playground-history-sidebar-width, 256px);"
          >
            <.execution_history
              executions={@executions}
              selected_execution_id={@selected_execution_id}
            />
          </div>
        </div>
      </div>

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
