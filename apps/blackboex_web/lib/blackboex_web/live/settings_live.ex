defmodule BlackboexWeb.SettingsLive do
  @moduledoc """
  Tabbed settings page with Profile, Organization, API Keys, Billing, and Security tabs.
  """
  use BlackboexWeb, :live_view

  import Ecto.Query, warn: false
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Avatar
  import BlackboexWeb.Components.Shared.DescriptionList

  alias Blackboex.{Audit, Billing}

  @tabs ~w(profile organization billing security)

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "profile")
    tab = if tab in @tabs, do: tab, else: "profile"

    socket =
      socket
      |> assign(:active_tab, tab)
      |> load_tab_data(tab)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-cog-6-tooth" class="size-5 text-slate-400" /> Settings
        </span>
      </.header>

      <div class="border-b mb-6">
        <nav class="flex gap-1">
          <.link
            :for={tab <- tabs()}
            patch={~p"/settings?tab=#{tab}"}
            class={[
              "flex items-center gap-1.5 px-4 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@active_tab == tab,
                do: "border-primary text-primary",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            <.icon name={tab_icon(tab)} class={"size-3.5 #{tab_icon_color(tab)}"} />
            {tab_label(tab)}
          </.link>
        </nav>
      </div>

      {render_tab(assigns)}
    </div>
    """
  end

  defp render_tab(%{active_tab: "profile"} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-user-circle" class="size-4 text-blue-400" /> Profile
        </h2>

        <div class="flex items-center gap-4 mb-6 mt-4">
          <.avatar class="h-12 w-12">
            <.avatar_fallback class="bg-primary/10 text-primary font-bold">
              {String.first(@current_scope.user.email) |> String.upcase()}
            </.avatar_fallback>
          </.avatar>
          <div>
            <p class="font-medium">{@current_scope.user.email}</p>
            <p class="text-sm text-muted-foreground">
              Member since {Calendar.strftime(@current_scope.user.inserted_at, "%B %Y")}
            </p>
          </div>
        </div>

        <.description_list>
          <:item label="Email">{@current_scope.user.email}</:item>
          <:item label="Account Created">
            {Calendar.strftime(@current_scope.user.inserted_at, "%B %d, %Y")}
          </:item>
        </.description_list>

        <div class="mt-4">
          <.button navigate={~p"/users/settings"} variant="default" size="sm">
            <.icon name="hero-pencil-square" class="mr-1.5 size-3.5 text-blue-400" />
            Edit Email & Password
          </.button>
        </div>
      </.card_content>
    </.card>
    """
  end

  defp render_tab(%{active_tab: "organization", current_scope: %{organization: nil}} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-building-office-2" class="size-4 text-violet-400" /> Organization
        </h2>
        <p class="text-muted-foreground mt-4">No organization selected.</p>
      </.card_content>
    </.card>
    """
  end

  defp render_tab(%{active_tab: "organization"} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-building-office-2" class="size-4 text-violet-400" /> Organization
        </h2>
        <div class="mt-4">
          <.description_list>
            <:item label="Name">{@current_scope.organization.name}</:item>
            <:item label="Slug">
              <span class="font-mono text-sm">{@current_scope.organization.slug}</span>
            </:item>
            <:item label="Plan">
              <.badge>{to_string(@current_scope.organization.plan)}</.badge>
            </:item>
            <:item label="Your Role">
              <.badge variant="outline">{to_string(@current_scope.membership.role)}</.badge>
            </:item>
          </.description_list>
        </div>

        <div :if={@members != []} class="mt-6">
          <h3 class="flex items-center gap-1.5 font-semibold mb-2">
            <.icon name="hero-user-group" class="size-4 text-blue-400" /> Members
          </h3>
          <div class="space-y-2">
            <div
              :for={member <- @members}
              class="flex items-center justify-between p-2 border rounded"
            >
              <span class="text-sm">{member.user.email}</span>
              <.badge variant="outline">{to_string(member.role)}</.badge>
            </div>
          </div>
        </div>
      </.card_content>
    </.card>
    """
  end

  defp render_tab(%{active_tab: "billing", current_scope: %{organization: nil}} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-credit-card" class="size-4 text-emerald-400" /> Billing
        </h2>
        <p class="text-muted-foreground mt-4">No organization selected.</p>
      </.card_content>
    </.card>
    """
  end

  defp render_tab(%{active_tab: "billing"} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-credit-card" class="size-4 text-emerald-400" /> Billing
        </h2>
        <div class="mt-4">
          <.description_list>
            <:item label="Current Plan">
              <span class="font-semibold capitalize">
                {to_string(@current_scope.organization.plan)}
              </span>
            </:item>
            <:item :if={@subscription} label="Status">
              <.badge class={subscription_classes(@subscription.status)}>
                {@subscription.status}
              </.badge>
            </:item>
          </.description_list>
        </div>

        <div class="flex gap-2 mt-4">
          <.button navigate={~p"/billing"} variant="primary" size="sm">
            <.icon name="hero-sparkles" class="mr-1.5 size-3.5 text-amber-300" /> View Plans
          </.button>
          <.button navigate={~p"/billing/manage"} variant="default" size="sm">
            <.icon name="hero-credit-card" class="mr-1.5 size-3.5 text-emerald-400" />
            Manage Subscription
          </.button>
        </div>
      </.card_content>
    </.card>
    """
  end

  defp render_tab(%{active_tab: "security"} = assigns) do
    ~H"""
    <.card>
      <.card_content class="pt-6">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-shield-check" class="size-4 text-teal-400" /> Security & Audit
        </h2>

        <div :if={@audit_logs == []} class="mt-4 text-muted-foreground">
          No recent activity.
        </div>

        <div :if={@audit_logs != []} class="mt-4">
          <h3 class="flex items-center gap-1.5 font-semibold mb-2">
            <.icon name="hero-clock" class="size-4 text-amber-400" /> Recent Activity
          </h3>
          <div class="space-y-2">
            <div
              :for={log <- @audit_logs}
              class="flex items-center justify-between p-2 border rounded text-sm"
            >
              <div>
                <span class="font-medium">{log.action}</span>
                <span :if={log.resource_type} class="text-muted-foreground ml-2">
                  {log.resource_type}
                </span>
              </div>
              <span class="text-muted-foreground text-xs">
                {Calendar.strftime(log.inserted_at, "%b %d, %H:%M")}
              </span>
            </div>
          </div>
        </div>

        <div class="mt-6">
          <.button navigate={~p"/users/settings"} variant="default" size="sm">
            <.icon name="hero-lock-closed" class="mr-1.5 size-3.5 text-amber-400" /> Change Password
          </.button>
        </div>
      </.card_content>
    </.card>
    """
  end

  defp load_tab_data(socket, "organization") do
    case socket.assigns.current_scope.organization do
      nil ->
        assign(socket, members: [])

      org ->
        members =
          Blackboex.Organizations.Membership
          |> where([m], m.organization_id == ^org.id)
          |> preload(:user)
          |> Blackboex.Repo.all()

        assign(socket, members: members)
    end
  end

  defp load_tab_data(socket, "billing") do
    case socket.assigns.current_scope.organization do
      nil ->
        assign(socket, subscription: nil)

      org ->
        subscription = Billing.get_subscription(org.id)
        assign(socket, subscription: subscription)
    end
  end

  defp load_tab_data(socket, "security") do
    user = socket.assigns.current_scope.user
    audit_logs = Audit.list_user_logs(user.id, limit: 20)
    assign(socket, audit_logs: audit_logs)
  end

  defp load_tab_data(socket, _tab) do
    socket
  end

  defp tab_icon("profile"), do: "hero-user-circle"
  defp tab_icon("organization"), do: "hero-building-office-2"
  defp tab_icon("billing"), do: "hero-credit-card"
  defp tab_icon("security"), do: "hero-shield-check"
  defp tab_icon(_), do: "hero-squares-2x2"

  defp tab_icon_color("profile"), do: "text-blue-400"
  defp tab_icon_color("organization"), do: "text-violet-400"
  defp tab_icon_color("billing"), do: "text-emerald-400"
  defp tab_icon_color("security"), do: "text-teal-400"
  defp tab_icon_color(_), do: "text-muted-foreground"

  defp tab_label("profile"), do: "Profile"
  defp tab_label("organization"), do: "Organization"
  defp tab_label("billing"), do: "Billing"
  defp tab_label("security"), do: "Security"

  defp tabs, do: @tabs
end
