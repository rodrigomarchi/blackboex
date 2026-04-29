defmodule BlackboexWeb.OrgSettingsLive do
  @moduledoc """
  Organization settings.
  Tabbed layout: Dashboard (default), General, Members.
  Dashboard tab embeds the full metrics dashboard with sub-navigation.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.DashboardLive.Content

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Organizations
  alias BlackboexWeb.DashboardLive.Scope

  @dashboard_actions [:dashboard, :apis, :flows, :llm]
  @valid_periods ~w(24h 7d 30d)
  @default_period "24h"

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    changeset = if org, do: Organizations.Organization.changeset(org, %{}), else: nil

    {:ok,
     socket
     |> assign(:org, org)
     |> assign(:form, changeset && to_form(changeset))
     |> assign(:scope, nil)
     |> assign(:base_path, "")
     |> assign(:period, @default_period)
     |> assign(:summary, nil)
     |> assign(:metrics, nil)
     |> assign(:series, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_content(socket, socket.assigns.live_action, params)}
  end

  defp load_content(socket, action, params) when action in @dashboard_actions do
    scope = Scope.from_socket(socket, params)
    org = socket.assigns.org
    base_path = if scope, do: Scope.base_path(scope, org, nil), else: ""
    period = normalize_period(params["period"])

    data =
      case action do
        :dashboard ->
          %{summary: DashboardQueries.overview_summary(scope)}

        :apis ->
          %{metrics: DashboardQueries.api_metrics(scope, period)}

        :flows ->
          %{metrics: DashboardQueries.flow_metrics(scope, period)}

        :llm ->
          %{
            metrics: DashboardQueries.llm_metrics(scope, period),
            series: DashboardQueries.llm_usage_series(scope, period)
          }
      end

    socket
    |> assign(:page_title, "Dashboard")
    |> assign(:scope, scope)
    |> assign(:base_path, base_path)
    |> assign(:period, period)
    |> assign(data)
  end

  defp load_content(socket, :general, _params) do
    org = socket.assigns.org
    assign(socket, :page_title, "#{(org && org.name) || "Org"} Settings")
  end

  defp normalize_period(p) when p in @valid_periods, do: p
  defp normalize_period(_), do: @default_period

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
    <.page_header icon="hero-building-office-2" icon_class="text-accent-blue" title="Organization Settings" />
    <.page>
      <.org_settings_tabs current_scope={@current_scope} active={tab_active(@live_action)} />

      <%= if @live_action in [:dashboard, :apis, :flows, :llm, :usage] do %>
        <.dashboard_nav active={nav_key(@live_action)} base_path={@base_path} />
        <%= if @live_action == :dashboard do %>
          <.overview_content summary={@summary} />
        <% end %>
        <%= if @live_action == :apis do %>
          <.apis_content metrics={@metrics} period={@period} base_path={@base_path} />
        <% end %>
        <%= if @live_action == :flows do %>
          <.flows_content metrics={@metrics} period={@period} base_path={@base_path} />
        <% end %>
        <%= if @live_action == :llm do %>
          <.llm_content metrics={@metrics} series={@series} period={@period} base_path={@base_path} />
        <% end %>
      <% end %>

      <%= if @live_action == :general do %>
        <div class="max-w-lg space-y-4">
          <.section_heading>General</.section_heading>

          <.form :let={f} for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <.input field={f[:name]} type="text" label="Organization Name" required />
            <.input field={f[:slug]} type="text" label="Slug" disabled />
            <.form_actions spacing="tight">
              <.button type="submit" variant="primary">Save Changes</.button>
            </.form_actions>
          </.form>
        </div>
      <% end %>
    </.page>
    """
  end

  defp tab_active(action) when action in [:dashboard, :apis, :flows, :llm],
    do: "dashboard"

  defp tab_active(:general), do: "general"

  defp nav_key(:dashboard), do: :overview
  defp nav_key(action), do: action

  @doc """
  Shared tab navigation for org settings pages.
  Used by OrgSettingsLive and OrgMemberLive.
  """
  attr :current_scope, :map, required: true
  attr :active, :string, required: true

  @spec org_settings_tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def org_settings_tabs(assigns) do
    ~H"""
    <nav class="flex gap-1 border-b">
      <.settings_tab
        label="Dashboard"
        href={org_path(@current_scope, "/settings")}
        active={@active == "dashboard"}
      />
      <.settings_tab
        label="General"
        href={org_path(@current_scope, "/settings/general")}
        active={@active == "general"}
      />
      <.settings_tab
        label="Members"
        href={org_path(@current_scope, "/members")}
        active={@active == "members"}
      />
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false

  defp settings_tab(assigns) do
    ~H"""
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
    """
  end
end
