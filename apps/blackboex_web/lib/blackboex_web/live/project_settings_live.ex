defmodule BlackboexWeb.ProjectSettingsLive do
  @moduledoc """
  Project settings.
  Allows project admins to rename/edit the project.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.UI.SectionHeading

  alias Blackboex.Projects

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.current_scope.project
    changeset = if project, do: Projects.Project.changeset(project, %{}), else: nil

    {:ok,
     socket
     |> assign(:page_title, "Project Settings")
     |> assign(:project, project)
     |> assign(:form, changeset && to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.Project.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    case Projects.update_project(socket.assigns.project, params) do
      {:ok, project} ->
        changeset = Projects.Project.changeset(project, %{})

        {:noreply,
         socket
         |> assign(:project, project)
         |> assign(:form, to_form(changeset))
         |> put_flash(:info, "Project updated successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-cog-6-tooth" class="size-5 text-accent-blue" /> Project Settings
        </span>
        <:subtitle>Manage your project</:subtitle>
      </.header>

      <div class="max-w-lg space-y-8">
        <div class="space-y-3">
          <.section_heading>General</.section_heading>

          <.form :let={f} for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <.input field={f[:name]} type="text" label="Project Name" required />
            <.input field={f[:description]} type="textarea" label="Description" />
            <.input field={f[:slug]} type="text" label="Slug" disabled />
            <.form_actions spacing="tight">
              <.button type="submit" variant="primary">Save Changes</.button>
            </.form_actions>
          </.form>
        </div>
      </div>
    </.page>
    """
  end
end
