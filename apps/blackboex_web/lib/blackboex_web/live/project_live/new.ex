defmodule BlackboexWeb.ProjectLive.New do
  @moduledoc """
  Creates a new project for the current organization.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "New Project", form: to_form(%{"name" => ""}))}
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    user = scope.user

    case Blackboex.Projects.create_project(org, user, %{name: name}) do
      {:ok, %{project: project}} ->
        {:noreply, push_navigate(socket, to: "/orgs/#{org.slug}/projects/#{project.slug}")}

      {:error, _op, %Ecto.Changeset{} = cs, _changes} ->
        errors = Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
        {:noreply, assign(socket, form: to_form(errors))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header icon="hero-folder-plus" icon_class="text-accent-blue" title="New Project" />
    <.page>
      <.form for={@form} phx-submit="create">
        <.input field={@form[:name]} label="Name" />
        <.button type="submit">Create</.button>
      </.form>
    </.page>
    """
  end
end
