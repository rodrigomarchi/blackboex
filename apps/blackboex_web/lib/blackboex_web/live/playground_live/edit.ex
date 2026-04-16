defmodule BlackboexWeb.PlaygroundLive.Edit do
  @moduledoc """
  Single-cell code editor and REPL for Playgrounds.
  Executes Elixir code in a sandboxed environment with execution history.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Editor.ExecutionHistory
  import BlackboexWeb.Components.Editor.PageHeader
  import BlackboexWeb.Components.Editor.PlaygroundTree
  import BlackboexWeb.Components.Editor.TerminalOutput
  import BlackboexWeb.Components.Shared.PlaygroundEditorField

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
        playgrounds = Playgrounds.list_playgrounds(project.id)
        executions = Playgrounds.list_executions(playground.id)
        {selected, selected_id} = select_latest(executions)

        {:ok,
         assign(socket,
           playground: playground,
           playgrounds: playgrounds,
           form: to_form(Playgrounds.change_playground(playground)),
           page_title: playground.name,
           output: playground.last_output,
           running: false,
           executions: executions,
           selected_execution_id: selected_id,
           selected_execution: selected,
           confirm: nil
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
        playgrounds = Playgrounds.list_playgrounds(project.id)

        {:noreply,
         socket
         |> assign(playgrounds: playgrounds)
         |> put_flash(:info, "Playground \"#{params["slug"] || pg.slug}\" deleted.")}
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

  # ── Helpers ───────────────────────────────────────────────

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
      <%!-- Left sidebar: playground tree --%>
      <div class="w-64 shrink-0 hidden md:block">
        <.playground_tree
          playgrounds={@playgrounds}
          current_playground_id={@playground.id}
        />
      </div>

      <%!-- Center: editor + output + history --%>
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
              class="h-1 shrink-0 bg-border hover:bg-primary/50 transition-colors cursor-row-resize"
            />

            <%!-- Output pane --%>
            <div id="output-pane" class="shrink-0 overflow-hidden" style="height: 240px;">
              <.terminal_output
                output={if @selected_execution, do: @selected_execution.output}
                status={if @selected_execution, do: @selected_execution.status}
                duration_ms={if @selected_execution, do: @selected_execution.duration_ms}
                run_number={if @selected_execution, do: @selected_execution.run_number}
              />
            </div>
          </div>

          <%!-- Horizontal resize handle --%>
          <div
            data-resize-handle
            data-resize-direction="horizontal"
            data-resize-target="history-sidebar"
            class="w-1 shrink-0 bg-border hover:bg-primary/50 transition-colors cursor-col-resize hidden md:block"
          />

          <%!-- Right sidebar: execution history --%>
          <div
            id="history-sidebar"
            class="shrink-0 overflow-hidden hidden md:block"
            style="width: 256px;"
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
