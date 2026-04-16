defmodule BlackboexWeb.PageLive.Edit do
  @moduledoc """
  Markdown editor for Pages. Split-pane with live preview.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Editor.PageHeader
  import BlackboexWeb.Components.Shared.CodeEditorField

  alias Blackboex.Pages

  @impl true
  def mount(%{"page_slug" => slug}, _session, socket) do
    project = socket.assigns.current_scope.project

    case Pages.get_page_by_slug(project.id, slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: project_path(socket.assigns.current_scope, "/pages"))}

      page ->
        {:ok,
         assign(socket,
           page: page,
           form: to_form(Pages.change_page(page)),
           page_title: page.title,
           preview_html: render_markdown(page.content)
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"page" => page_params}, socket) do
    changeset =
      socket.assigns.page
      |> Pages.Page.update_changeset(page_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("update_content", %{"value" => content}, socket) do
    {:noreply,
     assign(socket,
       content: content,
       preview_html: render_markdown(content)
     )}
  end

  @impl true
  def handle_event("save", %{"page" => page_params}, socket) do
    # Merge CodeMirror content into form params
    page_params =
      Map.put(page_params, "content", socket.assigns[:content] || socket.assigns.page.content)

    case Pages.update_page(socket.assigns.page, page_params) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(
           page: page,
           form: to_form(Pages.change_page(page)),
           preview_html: render_markdown(page.content)
         )
         |> put_flash(:info, "Page saved")}

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <.editor_page_header
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
        </:badge>
      </.editor_page_header>

      <div class="flex flex-1 min-h-0">
        <%!-- Editor pane --%>
        <div class="flex-1 flex flex-col overflow-hidden border-r">
          <div class="p-4 border-b">
            <.form for={@form} phx-change="validate" phx-submit="save">
              <.input field={@form[:title]} label="Title" />
              <.form_actions spacing="tight" class="mt-3">
                <.button type="submit" variant="primary">Save</.button>
              </.form_actions>
            </.form>
          </div>
          <div class="flex-1 min-h-0">
            <.code_editor_field
              id="page-content-editor"
              value={@page.content || ""}
              language="markdown"
              readonly={false}
              minimal={false}
              max_height="max-h-full"
              height="100%"
              event="update_content"
              field="content"
            />
          </div>
        </div>

        <%!-- Preview pane --%>
        <div class="flex-1 overflow-auto p-4 prose prose-sm dark:prose-invert max-w-none">
          {Phoenix.HTML.raw(@preview_html)}
        </div>
      </div>
    </div>
    """
  end

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(content) do
    case Earmark.as_html(content) do
      {:ok, html, _} -> HtmlSanitizeEx.markdown_html(html)
      {:error, _, _} -> Phoenix.HTML.html_escape(content) |> Phoenix.HTML.safe_to_string()
    end
  end
end
