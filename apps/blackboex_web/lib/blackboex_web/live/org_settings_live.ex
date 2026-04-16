defmodule BlackboexWeb.OrgSettingsLive do
  @moduledoc """
  Organization settings.
  Tabbed layout: General, Members, Billing, Security, Usage.
  Members and Billing tabs navigate to their existing dedicated pages.
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
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
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
          <.icon name="hero-building-office-2" class="size-5 text-accent-blue" />
          Organization Settings
        </span>
        <:subtitle>Manage your organization</:subtitle>
      </.header>

      <.org_settings_tabs current_scope={@current_scope} active="general" />

      <div class="mt-6 max-w-lg space-y-8">
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

        <%!-- Security placeholder --%>
        <div class="space-y-3">
          <.section_heading>Security</.section_heading>
          <p class="text-sm text-muted-foreground">
            Security settings coming soon. This will include SSO, 2FA enforcement, and session management.
          </p>
        </div>

        <%!-- Usage placeholder --%>
        <div class="space-y-3">
          <.section_heading>Usage & Quotas</.section_heading>
          <p class="text-sm text-muted-foreground">
            Usage overview coming soon. View API invocations, LLM usage, and storage quotas.
          </p>
        </div>
      </div>
    </.page>
    """
  end

  @doc """
  Shared tab navigation for org settings pages.
  Used by OrgSettingsLive, OrgMemberLive, and BillingLive to show consistent tabs.
  """
  attr :current_scope, :map, required: true
  attr :active, :string, required: true

  def org_settings_tabs(assigns) do
    ~H"""
    <nav class="mt-4 flex gap-1 border-b">
      <.settings_tab
        label="General"
        href={org_path(@current_scope, "/settings")}
        active={@active == "general"}
      />
      <.settings_tab
        label="Members"
        href={org_path(@current_scope, "/members")}
        active={@active == "members"}
      />
      <.settings_tab
        label="Billing"
        href={org_path(@current_scope, "/billing")}
        active={@active == "billing"}
      />
      <.settings_tab
        label="Security"
        href={org_path(@current_scope, "/settings")}
        active={@active == "security"}
        disabled
      />
      <.settings_tab
        label="Usage"
        href={org_path(@current_scope, "/settings")}
        active={@active == "usage"}
        disabled
      />
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :disabled, :boolean, default: false

  defp settings_tab(assigns) do
    ~H"""
    <%= if @disabled do %>
      <span class="px-4 py-2 text-sm font-medium border-b-2 -mb-px border-transparent text-muted-foreground/50 cursor-not-allowed">
        {@label}
        <span class="text-[10px] ml-1">(soon)</span>
      </span>
    <% else %>
      <.link
        navigate={@href}
        class={[
          "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
          if(@active,
            do: "border-primary text-foreground",
            else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
          )
        ]}
      >
        {@label}
      </.link>
    <% end %>
    """
  end
end
