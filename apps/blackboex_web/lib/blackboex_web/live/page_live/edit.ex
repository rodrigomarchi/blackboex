defmodule BlackboexWeb.PageLive.Edit do
  @moduledoc """
  Notion-like page editor with WYSIWYG Tiptap editor.
  Navigation between pages is handled by the app sidebar's tree view.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Editor.PageHeader
  import BlackboexWeb.Components.Editor.SaveIndicator
  import BlackboexWeb.Components.Shared.TiptapEditorField

  alias Blackboex.Pages
  alias Blackboex.Policy

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
        tree = Pages.list_page_tree(project.id)

        {:ok,
         assign(socket,
           page: page,
           form: to_form(Pages.change_page(page)),
           page_title: page.title,
           page_tree: tree,
           expanded_ids: expanded_ids_for(tree, page.id),
           save_status: :saved,
           confirm: nil
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full overflow-hidden">
      <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
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
            <.save_indicator status={@save_status} />
          </:badge>
        </.editor_page_header>

        <%!-- Inline title --%>
        <div class="px-8 pt-6 pb-2">
          <.form for={@form} phx-change="validate_title" phx-submit="save_title">
            <input
              type="text"
              name={@form[:title].name}
              value={@form[:title].value}
              placeholder="Untitled"
              class="w-full text-3xl font-bold bg-transparent border-none shadow-none p-0 focus:ring-0 focus:outline-none text-foreground placeholder:text-muted-foreground"
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

  # ── Events ─────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", %{"action" => "delete"} = params, socket) do
    title = params["title"] || "this page"

    confirm = %{
      title: "Delete page?",
      description:
        "\"#{title}\" and all of its sub-pages will be permanently removed. This action cannot be undone.",
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

    with :ok <- Policy.authorize_and_track(:page_delete, scope, org),
         page when not is_nil(page) <- Pages.get_page(project.id, id),
         {:ok, _} <- Pages.delete_page(page) do
      if page.id == socket.assigns.page.id do
        {:noreply,
         socket
         |> put_flash(:info, "Page deleted.")
         |> push_navigate(to: project_path(scope, "/pages"))}
      else
        tree = Pages.list_page_tree(project.id)

        {:noreply,
         socket
         |> assign(page_tree: tree)
         |> put_flash(:info, "Page \"#{params["slug"] || page.slug}\" deleted.")}
      end
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized to delete this page.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Page not found.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete page.")}
    end
  end

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

  @impl true
  def handle_event("select_page", %{"slug" => slug}, socket) do
    scope = socket.assigns.current_scope
    path = project_path(scope, "/pages/#{slug}/edit")
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("toggle_tree_node", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_ids

    expanded =
      if id in expanded do
        List.delete(expanded, id)
      else
        [id | expanded]
      end

    {:noreply, assign(socket, expanded_ids: expanded)}
  end

  @impl true
  def handle_event("new_page", _params, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    user = scope.user

    attrs = %{
      title: "Untitled",
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user.id
    }

    case Pages.create_page(attrs) do
      {:ok, page} ->
        path = project_path(scope, "/pages/#{page.slug}/edit")
        {:noreply, push_navigate(socket, to: path)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create page")}
    end
  end

  @impl true
  def handle_event("new_child_page", %{"parent-id" => parent_id}, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    user = scope.user

    attrs = %{
      title: "Untitled",
      parent_id: parent_id,
      organization_id: project.organization_id,
      project_id: project.id,
      user_id: user.id
    }

    case Pages.create_page(attrs) do
      {:ok, page} ->
        path = project_path(scope, "/pages/#{page.slug}/edit")
        {:noreply, push_navigate(socket, to: path)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create page")}
    end
  end

  # ── Private ────────────────────────────────────────────────

  defp expanded_ids_for(tree, current_page_id) do
    # Walk the tree and expand all ancestors of the current page
    find_ancestors(tree, current_page_id, [])
  end

  defp find_ancestors([], _target_id, _path), do: []

  defp find_ancestors([node | rest], target_id, path) do
    if node.page.id == target_id do
      path
    else
      new_path = [node.page.id | path]

      case find_ancestors(node.children, target_id, new_path) do
        [] -> find_ancestors(rest, target_id, path)
        found -> found
      end
    end
  end
end
