defmodule BlackboexWeb.ProjectSettingsLive do
  @moduledoc """
  Project settings.
  Tabbed layout: Dashboard (default), General, Members, API Keys, Env Vars, LLM Integrations.
  Dashboard tab embeds the full metrics dashboard with sub-navigation.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.ProjectSettingsTabs
  import BlackboexWeb.DashboardLive.Content

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Projects
  alias BlackboexWeb.DashboardLive.Scope

  @dashboard_actions [:dashboard, :apis, :flows, :llm]
  @valid_periods ~w(24h 7d 30d)
  @default_period "24h"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    org = scope.organization
    changeset = if project, do: Projects.Project.changeset(project, %{}), else: nil

    {:ok,
     socket
     |> assign(:org, org)
     |> assign(:project, project)
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
    project = socket.assigns.project
    base_path = if scope, do: Scope.base_path(scope, org, project), else: ""
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
    project = socket.assigns.project
    assign(socket, :page_title, "#{(project && project.name) || "Project"} Settings")
  end

  defp normalize_period(p) when p in @valid_periods, do: p
  defp normalize_period(_), do: @default_period

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

      <.project_settings_tabs
        :if={@project && @org}
        active={tab_active(@live_action)}
        org_slug={@org.slug}
        project_slug={@project.slug}
      />

      <%= if @live_action in [:dashboard, :apis, :flows, :llm] do %>
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
            <.input field={f[:name]} type="text" label="Project Name" required />
            <.input field={f[:description]} type="textarea" label="Description" />
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

  defp tab_active(action) when action in [:dashboard, :apis, :flows, :llm], do: :dashboard
  defp tab_active(:general), do: :general

  defp nav_key(:dashboard), do: :overview
  defp nav_key(action), do: action
end
