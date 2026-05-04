defmodule BlackboexWeb.PageLive.Edit do
  @moduledoc """
  Notion-like page editor with WYSIWYG Tiptap editor.
  Navigation between pages is handled by the app sidebar's tree view.
  """
  use BlackboexWeb, :live_view

  require Logger

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Editor.PageChatPanel
  import BlackboexWeb.Components.Editor.SaveIndicator
  import BlackboexWeb.Components.Shared.TiptapEditorField

  alias Blackboex.PageAgent
  alias Blackboex.PageAgent.StreamManager
  alias Blackboex.PageConversations
  alias Blackboex.Pages
  alias Blackboex.ProjectEnvVars

  @max_chat_messages 200

  @impl true
  def mount(%{"page_slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    org = scope.organization

    case Pages.get_page_by_slug(project.id, slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: project_path(socket.assigns.current_scope, "/pages"))}

      page ->
        chat_messages = load_chat_messages(page.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Blackboex.PubSub,
            StreamManager.page_topic(page.organization_id, page.id)
          )
        end

        {:ok,
         assign(socket,
           page: page,
           form: to_form(Pages.change_page(page)),
           page_title: page.title,
           save_status: :saved,
           chat_open: true,
           chat_messages: chat_messages,
           chat_input: "",
           chat_loading: false,
           chat_slow_timer: nil,
           current_run_id: nil,
           current_stream: nil,
           llm_configured?: llm_configured?(project.id),
           configure_url: ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations"
         )}
    end
  end

  @spec llm_configured?(Ecto.UUID.t()) :: boolean()
  defp llm_configured?(project_id) do
    match?({:ok, _key}, ProjectEnvVars.get_llm_key(project_id, :anthropic))
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full overflow-hidden" id="page-edit-root" phx-hook="ResizablePanels">
      <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
        <.page_header
          title={@page.title}
          back_path={project_path(@current_scope, "/pages")}
          back_label="Pages"
        >
          <:badge>
            <.badge
              variant={if @page.status == "published", do: "default", else: "secondary"}
              class="cursor-pointer"
              phx-click="toggle_status"
            >
              {@page.status}
            </.badge>
            <.save_indicator status={@save_status} />
            <button
              type="button"
              phx-click="toggle_chat"
              class="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-xs px-2 py-1 rounded border border-border"
              title="Toggle AI chat"
            >
              <.icon name="hero-sparkles" class="size-3.5" /> Chat
            </button>
          </:badge>
        </.page_header>

        <%!-- Inline title --%>
        <div class="px-8 pt-6 pb-2">
          <.form for={@form} phx-change="validate_title" phx-submit="save_title">
            <input
              type="text"
              name={@form[:title].name}
              value={@form[:title].value}
              placeholder="Untitled"
              class="w-full text-lg font-bold bg-transparent border-none shadow-none p-0 focus:ring-0 focus:outline-none text-foreground placeholder:text-muted-foreground"
            />
          </.form>
        </div>

        <%!-- WYSIWYG editor --%>
        <div class="flex-1 px-8 py-2 overflow-y-auto">
          <.tiptap_editor_field
            id="page-tiptap-editor"
            value={@page.content || ""}
            event="update_content"
            field="content"
          />
        </div>
      </div>

      <%!-- Resizable Chat Sidebar --%>
      <%= if @chat_open do %>
        <div
          data-resize-handle
          data-resize-direction="horizontal"
          data-resize-target="page-chat-sidebar"
          data-resize-css-var="--page-chat-width"
          class="w-1 cursor-col-resize bg-border hover:bg-primary/50 transition-colors shrink-0"
        />
        <aside
          id="page-chat-sidebar"
          class="border-l shrink-0 overflow-hidden"
          style="width: var(--page-chat-width, 380px); min-width: 280px; max-width: 600px;"
        >
          <.page_chat_panel
            messages={@chat_messages}
            input={@chat_input}
            loading={@chat_loading}
            current_stream={@current_stream}
            llm_configured?={@llm_configured?}
            configure_url={@configure_url}
          />
        </aside>
      <% end %>
    </div>
    """
  end

  # ── Events ─────────────────────────────────────────────────

  @impl true
  def handle_event("update_content", %{"value" => content}, socket) do
    page = socket.assigns.page
    socket = assign(socket, save_status: :saving)

    case Pages.update_page(page, %{content: content}) do
      {:ok, updated_page} ->
        {:noreply, assign(socket, page: updated_page, save_status: :saved)}

      {:error, _changeset} ->
        {:noreply, assign(socket, save_status: :unsaved)}
    end
  end

  @impl true
  def handle_event("validate_title", %{"page" => %{"title" => title}}, socket) do
    changeset =
      socket.assigns.page
      |> Pages.Page.update_changeset(%{title: title})
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save_title", %{"page" => %{"title" => title}}, socket) do
    case Pages.update_page(socket.assigns.page, %{title: title}) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(page: page, form: to_form(Pages.change_page(page)), page_title: page.title)
         |> put_flash(:info, "Title saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("toggle_status", _params, socket) do
    page = socket.assigns.page
    new_status = if page.status == "published", do: "draft", else: "published"

    case Pages.update_page(page, %{status: new_status}) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(page: page, form: to_form(Pages.change_page(page)))
         |> put_flash(:info, "Status changed to #{new_status}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  # ── Chat (AI Agent) Events ─────────────────────────────────

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}
  end

  @impl true
  def handle_event("chat_input_change", %{"message" => value}, socket) do
    {:noreply, assign(socket, chat_input: value)}
  end

  @impl true
  def handle_event("send_chat", %{"message" => message}, socket) do
    message = String.trim(message)

    cond do
      message == "" -> {:noreply, socket}
      socket.assigns.chat_loading -> {:noreply, socket}
      true -> dispatch_send_chat(socket, message)
    end
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    if socket.assigns.chat_loading do
      {:noreply,
       put_flash(socket, :error, "Wait for the agent response before starting a new chat.")}
    else
      page = socket.assigns.page

      case PageConversations.start_new_conversation(
             page.id,
             page.organization_id,
             page.project_id
           ) do
        {:ok, _new_conv} ->
          {:noreply,
           socket
           |> assign(chat_messages: [], chat_input: "", current_stream: nil, current_run_id: nil)
           |> put_flash(:info, "New chat started.")}

        {:error, reason} ->
          require Logger
          Logger.warning("PageConversations.start_new_conversation failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Could not start a new chat.")}
      end
    end
  end

  # ── AI Agent PubSub ────────────────────────────────────────

  @impl true
  def handle_info({:run_started, %{run_id: run_id}}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Blackboex.PubSub, StreamManager.run_topic(run_id))
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
  def handle_info({:content_delta, %{delta: delta, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      {:noreply, assign(socket, current_stream: (socket.assigns.current_stream || "") <> delta)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_completed, %{content: content, summary: summary, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      cancel_chat_slow_timer(socket)
      project = socket.assigns.current_scope.project
      page = Pages.get_page(project.id, socket.assigns.page.id) || socket.assigns.page
      page = %{page | content: content}
      assistant_msg = %{role: "assistant", content: summary, run_id: run_id}

      {:noreply,
       assign(socket,
         page: page,
         chat_loading: false,
         chat_slow_timer: nil,
         current_run_id: nil,
         current_stream: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [assistant_msg])
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_failed, %{reason: reason, run_id: run_id}}, socket) do
    if socket.assigns.current_run_id == run_id do
      cancel_chat_slow_timer(socket)
      Logger.warning("PageAgent run #{run_id} failed: #{reason}")
      failure_msg = %{role: "system", content: "Agent failed. Try again."}

      {:noreply,
       socket
       |> assign(
         chat_loading: false,
         chat_slow_timer: nil,
         current_run_id: nil,
         current_stream: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [failure_msg])
       )
       |> put_flash(:error, "Agent failed. Try again.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:chat_slow_warning, socket) do
    if socket.assigns.chat_loading do
      warning = %{
        role: "system",
        content: "Agent is taking longer than expected... please wait (timeout: 3 min)."
      }

      {:noreply,
       assign(socket,
         chat_slow_timer: nil,
         chat_messages: cap_messages(socket.assigns.chat_messages ++ [warning])
       )}
    else
      {:noreply, assign(socket, chat_slow_timer: nil)}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private ────────────────────────────────────────────────

  defp load_chat_messages(page_id) do
    page_id
    |> PageConversations.list_active_conversation_events()
    |> Enum.map(&event_to_message/1)
    |> Enum.reject(&is_nil/1)
  end

  defp event_to_message(%{event_type: "user_message", content: content, inserted_at: ts}),
    do: %{role: "user", content: content, timestamp: ts}

  defp event_to_message(%{event_type: "assistant_message", content: content, inserted_at: ts}),
    do: %{role: "assistant", content: content, timestamp: ts}

  defp event_to_message(%{event_type: "completed", content: content, inserted_at: ts}),
    do: %{role: "assistant", content: content, timestamp: ts}

  defp event_to_message(_), do: nil

  defp cancel_chat_slow_timer(%{assigns: %{chat_slow_timer: nil}}), do: :ok
  defp cancel_chat_slow_timer(%{assigns: %{chat_slow_timer: ref}}), do: Process.cancel_timer(ref)

  defp dispatch_send_chat(socket, message) do
    case PageAgent.start(socket.assigns.page, socket.assigns.current_scope, message) do
      {:ok, _job} -> apply_send_chat_success(socket, message)
      {:error, reason} -> apply_send_chat_error(socket, reason)
    end
  end

  defp apply_send_chat_success(socket, message) do
    user_msg = %{role: "user", content: message}
    slow_timer = Process.send_after(self(), :chat_slow_warning, 30_000)

    {:noreply,
     assign(socket,
       chat_input: "",
       chat_loading: true,
       chat_slow_timer: slow_timer,
       chat_messages: cap_messages(socket.assigns.chat_messages ++ [user_msg]),
       chat_open: true
     )}
  end

  defp apply_send_chat_error(socket, :empty_message), do: {:noreply, socket}

  defp apply_send_chat_error(socket, :message_too_long),
    do: {:noreply, put_flash(socket, :error, "Message is too long. Shorten it and try again.")}

  defp apply_send_chat_error(socket, :limit_exceeded),
    do: {:noreply, put_flash(socket, :error, "Plan generation limit reached.")}

  defp apply_send_chat_error(socket, :agent_busy),
    do:
      {:noreply,
       put_flash(socket, :error, "A request is already in progress. Wait a few seconds.")}

  defp apply_send_chat_error(socket, reason) do
    Logger.warning("PageAgent.start failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to start the agent. Try again.")}
  end

  # Bound the in-memory chat history so very long sessions don't leak memory
  # and so the rendered DOM stays manageable. Older messages remain in the DB
  # and would re-hydrate on reconnect via load_chat_messages/1.
  defp cap_messages(messages) when length(messages) <= @max_chat_messages, do: messages
  defp cap_messages(messages), do: Enum.take(messages, -@max_chat_messages)
end
