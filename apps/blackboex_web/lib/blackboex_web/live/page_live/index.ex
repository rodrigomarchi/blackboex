defmodule BlackboexWeb.PageLive.Index do
  @moduledoc """
  Lists pages within a project. Supports inline create modal via :new action.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Modal

  alias Blackboex.Pages

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.current_scope.project

    pages =
      if project do
        Pages.list_pages(project.id)
      else
        []
      end

    {:ok,
     assign(socket,
       pages: pages,
       page_title: "Pages",
       changeset: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    case socket.assigns.live_action do
      :new ->
        changeset = Pages.change_page(%Pages.Page{}, %{})
        {:noreply, assign(socket, changeset: to_form(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_page", %{"page" => page_params}, socket) do
    scope = socket.assigns.current_scope

    attrs =
      Map.merge(page_params, %{
        "organization_id" => scope.organization.id,
        "project_id" => scope.project.id,
        "user_id" => scope.user.id
      })

    case Pages.create_page(attrs) do
      {:ok, page} ->
        {:noreply,
         socket
         |> put_flash(:info, "Page created")
         |> push_navigate(to: project_path(scope, "/pages/#{page.slug}/edit"))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_page", %{"id" => page_id}, socket) do
    project = socket.assigns.current_scope.project

    case Pages.get_page(project.id, page_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Page not found")}

      page ->
        case Pages.delete_page(page) do
          {:ok, _} ->
            pages = Pages.list_pages(project.id)
            {:noreply, socket |> assign(pages: pages) |> put_flash(:info, "Page deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete page")}
        end
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, push_navigate(socket, to: project_path(socket.assigns.current_scope, "/pages"))}
  end

  @impl true
  def handle_event("validate_page", %{"page" => page_params}, socket) do
    changeset =
      %Pages.Page{}
      |> Pages.Page.changeset(page_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-document-text" class="size-5 text-accent-sky" /> Pages
        </span>
        <:subtitle>Planning, documentation, and notes</:subtitle>
        <:actions>
          <.link navigate={project_path(@current_scope, "/pages/new")}>
            <.button variant="primary">
              <.icon name="hero-plus" class="mr-2 size-4" /> New Page
            </.button>
          </.link>
        </:actions>
      </.header>

      <%= if @pages == [] do %>
        <.empty_state
          icon="hero-document-text"
          title="No pages yet"
          description="Create your first page for planning, documentation, or notes."
        >
          <:actions>
            <.link navigate={project_path(@current_scope, "/pages/new")}>
              <.button variant="primary">Create Page</.button>
            </.link>
          </:actions>
        </.empty_state>
      <% else %>
        <.page_section>
          <.list_row
            :for={page <- @pages}
            class="hover:bg-accent/50 transition-colors"
          >
            <.link
              navigate={project_path(@current_scope, "/pages/#{page.slug}/edit")}
              class="flex-1 min-w-0"
            >
              <h3 class="font-medium">{page.title}</h3>
              <p class="text-sm text-muted-foreground">
                Updated {Calendar.strftime(page.updated_at, "%b %d, %Y")}
              </p>
            </.link>
            <div class="flex items-center gap-2 ml-4">
              <.badge variant={if page.status == "published", do: "default", else: "secondary"}>
                {page.status}
              </.badge>
              <.button
                variant="ghost"
                size="icon"
                class="h-8 w-8 text-destructive"
                phx-click="delete_page"
                phx-value-id={page.id}
                data-confirm="Are you sure you want to delete this page?"
              >
                <.icon name="hero-trash" class="size-4" />
              </.button>
            </div>
          </.list_row>
        </.page_section>
      <% end %>

      <.modal :if={@live_action == :new} show={true} on_close="close_modal" title="Create Page">
        <.form
          for={@changeset}
          phx-change="validate_page"
          phx-submit="create_page"
          class="space-y-4"
        >
          <.input field={@changeset[:title]} label="Title" required autofocus />
          <.form_actions spacing="tight">
            <.button type="submit" variant="primary">Create</.button>
            <.link navigate={project_path(@current_scope, "/pages")}>
              <.button type="button" variant="ghost">Cancel</.button>
            </.link>
          </.form_actions>
        </.form>
      </.modal>
    </.page>
    """
  end
end
