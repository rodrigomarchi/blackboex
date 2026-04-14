defmodule BlackboexWeb.OrgSettingsLive do
  @moduledoc """
  Organization settings.
  Allows owners to rename the organization.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.UI.SectionHeading

  alias Blackboex.Organizations

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    changeset = if org, do: Organizations.Organization.changeset(org, %{}), else: nil

    {:ok,
     socket
     |> assign(:page_title, "Organization Settings")
     |> assign(:org, org)
     |> assign(:form, changeset && to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.org
      |> Organizations.Organization.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"organization" => params}, socket) do
    case Organizations.update_organization(socket.assigns.org, params) do
      {:ok, org} ->
        changeset = Organizations.Organization.changeset(org, %{})

        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:form, to_form(changeset))
         |> put_flash(:info, "Organization updated successfully")}

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
          <.icon name="hero-cog-6-tooth" class="size-5 text-accent-blue" /> Organization Settings
        </span>
        <:subtitle>Manage your organization</:subtitle>
      </.header>

      <div class="max-w-lg space-y-8">
        <div class="space-y-3">
          <.section_heading>General</.section_heading>

          <.form :let={f} for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <.input field={f[:name]} type="text" label="Organization Name" required />
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
