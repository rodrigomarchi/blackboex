defmodule BlackboexWeb.ApiLive.Edit.DocsLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [render_markdown: 1]

  alias Blackboex.Apis
  alias Blackboex.Billing.Enforcement
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM
  alias Blackboex.LLM.Config
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, assign(socket, doc_generating: false, doc_gen_ref: nil)}
      {:error, socket} -> {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :doc_content, assigns.api.documentation_md)

    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="docs">
      <div class="p-6 overflow-y-auto h-full">
        <%= if @doc_content && @doc_content != "" do %>
          <div class="prose prose-sm dark:prose-invert max-w-none">
            {raw(render_markdown(@doc_content))}
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center py-16 text-center">
            <.icon name="hero-document-text" class="size-10 text-muted-foreground mb-4" />
            <p class="text-sm font-medium">No documentation yet</p>
            <p class="text-xs text-muted-foreground mt-1">
              Documentation is generated automatically after code generation completes.
            </p>
          </div>
        <% end %>
      </div>
    </.editor_shell>
    """
  end

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  def handle_event("generate_docs", _params, %{assigns: %{doc_generating: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("generate_docs", _params, socket) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        task = Task.async(fn -> DocGenerator.generate(api) end)
        {:noreply, assign(socket, doc_generating: true, doc_gen_ref: task.ref)}

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  @impl true
  def handle_info({ref, {:ok, %{doc: markdown, usage: usage}}}, socket)
      when ref == socket.assigns.doc_gen_ref do
    Process.demonitor(ref, [:flush])
    record_generation_usage(socket, "doc_generation", usage)

    case Apis.update_api(socket.assigns.api, %{documentation_md: markdown}) do
      {:ok, updated_api} ->
        {:noreply,
         socket
         |> assign(api: updated_api, doc_generating: false, doc_gen_ref: nil)
         |> put_flash(:info, "Documentation generated successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(doc_generating: false, doc_gen_ref: nil)
         |> put_flash(:error, "Failed to save documentation")}
    end
  end

  def handle_info({ref, {:error, _reason}}, socket)
      when ref == socket.assigns.doc_gen_ref do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(doc_generating: false, doc_gen_ref: nil)
     |> put_flash(:error, "Failed to generate documentation")}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when ref == socket.assigns.doc_gen_ref do
    {:noreply, assign(socket, doc_generating: false, doc_gen_ref: nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private ───────────────────────────────────────────────────────────

  @spec record_generation_usage(Phoenix.LiveView.Socket.t(), String.t(), map()) :: :ok
  defp record_generation_usage(socket, operation, usage) do
    scope = socket.assigns.current_scope
    provider = Config.default_provider()

    LLM.record_usage(%{
      user_id: scope.user.id,
      organization_id: socket.assigns.org.id,
      provider: to_string(provider.name),
      model: provider.model,
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      cost_cents: 0,
      operation: operation,
      api_id: socket.assigns.api.id,
      duration_ms: 0
    })
  end

  @spec shared_shell_assigns(map()) :: map()
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
end
