defmodule BlackboexWeb.PlaygroundLive.Edit do
  @moduledoc """
  Single-cell code editor and REPL for Playgrounds.
  Executes Elixir code in a sandboxed environment.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Editor.PageHeader
  import BlackboexWeb.Components.Shared.CodeEditorField

  alias Blackboex.Playgrounds

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
        {:ok,
         assign(socket,
           playground: playground,
           form: to_form(Playgrounds.change_playground(playground)),
           page_title: playground.name,
           output: playground.last_output,
           running: false
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_code", %{"value" => code}, socket) do
    {:noreply, assign(socket, current_code: code)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    code = socket.assigns[:current_code] || socket.assigns.playground.code
    self_pid = self()

    Task.start(fn ->
      result = Playgrounds.execute_code(socket.assigns.playground, code)
      send(self_pid, {:execution_result, result})
    end)

    {:noreply, assign(socket, running: true)}
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
  def handle_event("validate", %{"playground" => params}, socket) do
    changeset =
      socket.assigns.playground
      |> Playgrounds.Playground.update_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_info({:execution_result, result}, socket) do
    {output, playground} =
      case result do
        {:ok, playground} -> {playground.last_output, playground}
        {:error, reason} -> {"Error: #{reason}", socket.assigns.playground}
      end

    {:noreply, assign(socket, output: output, running: false, playground: playground)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
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

      <div class="flex flex-1 flex-col min-h-0">
        <%!-- Code editor --%>
        <div class="flex-1 min-h-0 border-b">
          <.code_editor_field
            id="playground-code-editor"
            value={@playground.code || ""}
            language="elixir"
            readonly={false}
            minimal={false}
            max_height="max-h-full"
            height="100%"
            event="update_code"
            field="code"
          />
        </div>

        <%!-- Output pane --%>
        <div class="h-48 shrink-0 overflow-auto bg-muted/50 p-4">
          <p class="text-xs font-medium text-muted-foreground mb-2">Output</p>
          <pre class="font-mono text-sm whitespace-pre-wrap">{@output || "No output yet. Click Run to execute."}</pre>
        </div>
      </div>
    </div>
    """
  end
end
