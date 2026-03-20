defmodule BlackboexWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard with platform-wide statistics.
  """
  use BlackboexWeb, :live_view

  import Ecto.Query, warn: false

  alias Blackboex.Repo

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    stats = load_stats()
    {:ok, assign(socket, stats: stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8">
      <h1 class="text-2xl font-bold mb-8">Admin Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <.stat_card title="Users" value={@stats.users} icon="hero-users" />
        <.stat_card title="Organizations" value={@stats.organizations} icon="hero-building-office" />
        <.stat_card title="APIs" value={@stats.apis} icon="hero-bolt" />
        <.stat_card title="Published APIs" value={@stats.published_apis} icon="hero-globe-alt" />
        <.stat_card title="Subscriptions" value={@stats.subscriptions} icon="hero-credit-card" />
        <.stat_card title="Audit Logs" value={@stats.audit_logs} icon="hero-document-text" />
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border shadow-sm">
      <div class="card-body">
        <div class="flex items-center gap-3">
          <.icon name={@icon} class="size-8 text-primary" />
          <div>
            <p class="text-sm text-base-content/60">{@title}</p>
            <p class="text-2xl font-bold">{@value}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_stats do
    %{
      users: Repo.aggregate(Blackboex.Accounts.User, :count),
      organizations: Repo.aggregate(Blackboex.Organizations.Organization, :count),
      apis: Repo.aggregate(Blackboex.Apis.Api, :count),
      published_apis:
        Blackboex.Apis.Api
        |> where([a], a.status == "published")
        |> Repo.aggregate(:count),
      subscriptions: Repo.aggregate(Blackboex.Billing.Subscription, :count),
      audit_logs: Repo.aggregate(Blackboex.Audit.AuditLog, :count)
    }
  end
end
