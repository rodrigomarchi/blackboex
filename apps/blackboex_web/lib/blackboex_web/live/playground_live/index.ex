defmodule BlackboexWeb.PlaygroundLive.Index do
  @moduledoc """
  Lists playgrounds within a project. Supports inline create modal via :new action.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal

  alias Blackboex.Playgrounds

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.current_scope.project

    playgrounds =
      if project do
        Playgrounds.list_playgrounds(project.id)
      else
        []
      end

    {:ok,
     assign(socket,
       playgrounds: playgrounds,
       page_title: "Playgrounds",
       changeset: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    case socket.assigns.live_action do
      :new ->
        changeset = Playgrounds.change_playground(%Playgrounds.Playground{}, %{})
        {:noreply, assign(socket, changeset: to_form(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_playground", %{"playground" => pg_params}, socket) do
    scope = socket.assigns.current_scope

    attrs =
      Map.merge(pg_params, %{
        "organization_id" => scope.organization.id,
        "project_id" => scope.project.id,
        "user_id" => scope.user.id
      })

    case Playgrounds.create_playground(attrs) do
      {:ok, playground} ->
        {:noreply,
         socket
         |> put_flash(:info, "Playground created")
         |> push_navigate(to: project_path(scope, "/playgrounds/#{playground.slug}/edit"))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_playground", %{"id" => pg_id}, socket) do
    project = socket.assigns.current_scope.project

    case Playgrounds.get_playground(project.id, pg_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Playground not found")}

      playground ->
        case Playgrounds.delete_playground(playground) do
          {:ok, _} ->
            playgrounds = Playgrounds.list_playgrounds(project.id)

            {:noreply,
             socket |> assign(playgrounds: playgrounds) |> put_flash(:info, "Playground deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete playground")}
        end
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     push_navigate(socket, to: project_path(socket.assigns.current_scope, "/playgrounds"))}
  end

  @impl true
  def handle_event("validate_playground", %{"playground" => pg_params}, socket) do
    changeset =
      %Playgrounds.Playground{}
      |> Playgrounds.Playground.changeset(pg_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-code-bracket" class="size-5 text-accent-emerald" /> Playgrounds
        </span>
        <:subtitle>Interactive Elixir code experimentation</:subtitle>
        <:actions>
          <.link navigate={project_path(@current_scope, "/playgrounds/new")}>
            <.button variant="primary">
              <.icon name="hero-plus" class="mr-2 size-4" /> New Playground
            </.button>
          </.link>
        </:actions>
      </.header>

      <%= if @playgrounds == [] do %>
        <.empty_state
          icon="hero-code-bracket"
          title="No playgrounds yet"
          description="Create an interactive playground to experiment with Elixir code."
        >
          <:actions>
            <.link navigate={project_path(@current_scope, "/playgrounds/new")}>
              <.button variant="primary">Create Playground</.button>
            </.link>
          </:actions>
        </.empty_state>
      <% else %>
        <.page_section>
          <.list_row
            :for={pg <- @playgrounds}
            class="hover:bg-accent/50 transition-colors"
          >
            <.link
              navigate={project_path(@current_scope, "/playgrounds/#{pg.slug}/edit")}
              class="flex-1 min-w-0"
            >
              <h3 class="font-medium">{pg.name}</h3>
              <p class="text-sm text-muted-foreground">
                Updated {Calendar.strftime(pg.updated_at, "%b %d, %Y")}
              </p>
            </.link>
            <div class="flex items-center gap-2 ml-4">
              <.icon name="hero-play" class="size-4 text-accent-emerald" />
              <.button
                variant="ghost"
                size="icon"
                class="h-8 w-8 text-destructive"
                phx-click="delete_playground"
                phx-value-id={pg.id}
                data-confirm="Are you sure you want to delete this playground?"
              >
                <.icon name="hero-trash" class="size-4" />
              </.button>
            </div>
          </.list_row>
        </.page_section>
      <% end %>

      <.modal
        :if={@live_action == :new}
        show={true}
        on_close="close_modal"
        title="Create Playground"
      >
        <.form
          for={@changeset}
          phx-change="validate_playground"
          phx-submit="create_playground"
          class="space-y-4"
        >
          <.input field={@changeset[:name]} label="Name" required autofocus />
          <.input field={@changeset[:description]} label="Description (optional)" />
          <.form_actions spacing="tight">
            <.button type="submit" variant="primary">Create</.button>
            <.link navigate={project_path(@current_scope, "/playgrounds")}>
              <.button type="button" variant="ghost">Cancel</.button>
            </.link>
          </.form_actions>
        </.form>
      </.modal>
    </.page>
    """
  end
end
