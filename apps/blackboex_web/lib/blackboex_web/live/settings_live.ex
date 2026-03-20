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
    <div class="max-w-4xl mx-auto py-8">
      <h1 class="text-2xl font-bold mb-6">Settings</h1>

      <div class="flex gap-8">
        <nav class="w-48 shrink-0">
          <ul class="space-y-1">
            <li :for={tab <- tabs()}>
              <.link
                patch={~p"/settings?tab=#{tab}"}
                class={[
                  "block px-3 py-2 rounded-md text-sm font-medium",
                  if(@active_tab == tab,
                    do: "bg-primary text-primary-content",
                    else: "hover:bg-base-200"
                  )
                ]}
              >
                {tab_label(tab)}
              </.link>
            </li>
          </ul>
        </nav>

        <div class="flex-1">
          {render_tab(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "profile"} = assigns) do
    ~H"""
    <div class="card bg-base-100 border shadow-sm">
      <div class="card-body">
        <h2 class="card-title">Profile</h2>
        <div class="mt-4 space-y-4">
          <div>
            <span class="text-sm text-base-content/60">Email</span>
            <p class="font-medium">{@current_scope.user.email}</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Account Created</span>
            <p class="text-sm">{Calendar.strftime(@current_scope.user.inserted_at, "%B %d, %Y")}</p>
          </div>
          <div class="mt-4">
            <.link navigate={~p"/users/settings"} class="btn btn-outline btn-sm">
              Edit Email & Password
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "organization"} = assigns) do
    ~H"""
    <div class="card bg-base-100 border shadow-sm">
      <div class="card-body">
        <h2 class="card-title">Organization</h2>
        <div class="mt-4 space-y-4">
          <div>
            <span class="text-sm text-base-content/60">Name</span>
            <p class="font-medium">{@current_scope.organization.name}</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Slug</span>
            <p class="font-mono text-sm">{@current_scope.organization.slug}</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Plan</span>
            <p>
              <span class="badge badge-primary capitalize">
                {to_string(@current_scope.organization.plan)}
              </span>
            </p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Your Role</span>
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
                <span class="badge badge-outline capitalize text-xs">{to_string(member.role)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_tab(%{active_tab: "billing"} = assigns) do
    ~H"""
    <div class="card bg-base-100 border shadow-sm">
      <div class="card-body">
        <h2 class="card-title">Billing</h2>
        <div class="mt-4 space-y-4">
          <div>
            <span class="text-sm text-base-content/60">Current Plan</span>
            <p class="font-semibold capitalize">{to_string(@current_scope.organization.plan)}</p>
          </div>

          <%= if @subscription do %>
            <div>
              <span class="text-sm text-base-content/60">Status</span>
              <p>
                <span class={["badge", subscription_badge(@subscription.status)]}>
                  {@subscription.status}
                </span>
              </p>
            </div>
          <% end %>

          <div class="flex gap-2 mt-4">
            <.link navigate={~p"/billing"} class="btn btn-primary btn-sm">
              View Plans
            </.link>
            <.link navigate={~p"/billing/manage"} class="btn btn-outline btn-sm">
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
    <div class="card bg-base-100 border shadow-sm">
      <div class="card-body">
        <h2 class="card-title">Security & Audit</h2>

        <div :if={@audit_logs == []} class="mt-4 text-base-content/60">
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
                <span :if={log.resource_type} class="text-base-content/60 ml-2">
                  {log.resource_type}
                </span>
              </div>
              <span class="text-base-content/60 text-xs">
                {Calendar.strftime(log.inserted_at, "%b %d, %H:%M")}
              </span>
            </div>
          </div>
        </div>

        <div class="mt-6">
          <.link navigate={~p"/users/settings"} class="btn btn-outline btn-sm">
            Change Password
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp load_tab_data(socket, "organization") do
    org_id = socket.assigns.current_scope.organization.id

    members =
      Blackboex.Organizations.Membership
      |> where([m], m.organization_id == ^org_id)
      |> preload(:user)
      |> Blackboex.Repo.all()

    assign(socket, members: members)
  end

  defp load_tab_data(socket, "billing") do
    org = socket.assigns.current_scope.organization
    subscription = Billing.get_subscription(org.id)
    assign(socket, subscription: subscription)
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

  defp subscription_badge("active"), do: "badge-success"
  defp subscription_badge("trialing"), do: "badge-info"
  defp subscription_badge("past_due"), do: "badge-warning"
  defp subscription_badge("canceled"), do: "badge-error"
  defp subscription_badge(_), do: "badge-ghost"

  defp tabs, do: @tabs
end
