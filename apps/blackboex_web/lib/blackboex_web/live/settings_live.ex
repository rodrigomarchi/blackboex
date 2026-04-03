defmodule BlackboexWeb.SettingsLive do
  @moduledoc """
  Tabbed settings page with Profile, Organization, API Keys, Billing, and Security tabs.
  """
  use BlackboexWeb, :live_view

  import Ecto.Query, warn: false

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
      <h1 class="text-2xl font-bold mb-6">Settings</h1>

      <div class="border-b mb-6">
        <nav class="flex gap-1">
          <.link
            :for={tab <- tabs()}
            patch={~p"/settings?tab=#{tab}"}
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@active_tab == tab,
                do: "border-primary text-primary",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
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
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Profile</h2>

        <div class="flex items-center gap-4 mb-6 mt-4">
          <div class="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10 text-primary font-bold">
            {String.first(@current_scope.user.email) |> String.upcase()}
          </div>
          <div>
            <p class="font-medium">{@current_scope.user.email}</p>
            <p class="text-sm text-muted-foreground">
              Member since {Calendar.strftime(@current_scope.user.inserted_at, "%B %Y")}
            </p>
          </div>
        </div>

        <div class="space-y-4">
          <div>
            <span class="text-sm text-muted-foreground">Email</span>
            <p class="font-medium">{@current_scope.user.email}</p>
          </div>
          <div>
            <span class="text-sm text-muted-foreground">Account Created</span>
            <p class="text-sm">{Calendar.strftime(@current_scope.user.inserted_at, "%B %d, %Y")}</p>
          </div>
          <div class="mt-4">
            <.link
              navigate={~p"/users/settings"}
              class="inline-flex items-center justify-center rounded-md border border-input bg-background px-3 py-1 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
            >
              Edit Email & Password
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "organization", current_scope: %{organization: nil}} = assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Organization</h2>
        <p class="text-muted-foreground mt-4">No organization selected.</p>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "organization"} = assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Organization</h2>
        <div class="mt-4 space-y-4">
          <div>
            <span class="text-sm text-muted-foreground">Name</span>
            <p class="font-medium">{@current_scope.organization.name}</p>
          </div>
          <div>
            <span class="text-sm text-muted-foreground">Slug</span>
            <p class="font-mono text-sm">{@current_scope.organization.slug}</p>
          </div>
          <div>
            <span class="text-sm text-muted-foreground">Plan</span>
            <p>
              <span class="inline-flex items-center rounded-full bg-primary px-2.5 py-0.5 text-xs font-semibold text-primary-foreground capitalize">
                {to_string(@current_scope.organization.plan)}
              </span>
            </p>
          </div>
          <div>
            <span class="text-sm text-muted-foreground">Your Role</span>
            <p class="capitalize">{to_string(@current_scope.membership.role)}</p>
          </div>

          <div :if={@members != []} class="mt-6">
            <h3 class="font-semibold mb-2">Members</h3>
            <div class="space-y-2">
              <div
                :for={member <- @members}
                class="flex items-center justify-between p-2 border rounded"
              >
                <span class="text-sm">{member.user.email}</span>
                <span class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold capitalize">
                  {to_string(member.role)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "billing", current_scope: %{organization: nil}} = assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Billing</h2>
        <p class="text-muted-foreground mt-4">No organization selected.</p>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "billing"} = assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Billing</h2>
        <div class="mt-4 space-y-4">
          <div>
            <span class="text-sm text-muted-foreground">Current Plan</span>
            <p class="font-semibold capitalize">{to_string(@current_scope.organization.plan)}</p>
          </div>

          <%= if @subscription do %>
            <div>
              <span class="text-sm text-muted-foreground">Status</span>
              <p>
                <span class={["inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold", subscription_badge(@subscription.status)]}>
                  {@subscription.status}
                </span>
              </p>
            </div>
          <% end %>

          <div class="flex gap-2 mt-4">
            <.link
              navigate={~p"/billing"}
              class="inline-flex items-center justify-center rounded-md bg-primary px-3 py-1 text-xs font-medium text-primary-foreground hover:bg-primary/90"
            >
              View Plans
            </.link>
            <.link
              navigate={~p"/billing/manage"}
              class="inline-flex items-center justify-center rounded-md border border-input bg-background px-3 py-1 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
            >
              Manage Subscription
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "security"} = assigns) do
    ~H"""
    <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
      <div class="p-6">
        <h2 class="text-lg font-semibold">Security & Audit</h2>

        <div :if={@audit_logs == []} class="mt-4 text-muted-foreground">
          No recent activity.
        </div>

        <div :if={@audit_logs != []} class="mt-4">
          <h3 class="font-semibold mb-2">Recent Activity</h3>
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
          <.link
            navigate={~p"/users/settings"}
            class="inline-flex items-center justify-center rounded-md border border-input bg-background px-3 py-1 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
          >
            Change Password
          </.link>
        </div>
      </div>
    </div>
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

  defp tab_label("profile"), do: "Profile"
  defp tab_label("organization"), do: "Organization"
  defp tab_label("billing"), do: "Billing"
  defp tab_label("security"), do: "Security"

  defp subscription_badge(status), do: subscription_classes(status)

  defp tabs, do: @tabs
end
