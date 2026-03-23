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
    <BlackboexWeb.Layouts.admin flash={@flash} current_url="/admin" live_resource={nil}>
      <div class="max-w-5xl mx-auto py-8">
        <h1 class="text-2xl font-bold mb-8">Admin Dashboard</h1>

        <h2 class="text-lg font-semibold mb-4">Core</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <.stat_card title="Users" value={@stats.users} icon="hero-users" href={~p"/admin/users"} />
          <.stat_card
            title="Organizations"
            value={@stats.organizations}
            icon="hero-building-office"
            href={~p"/admin/organizations"}
          />
          <.stat_card
            title="Memberships"
            value={@stats.memberships}
            icon="hero-user-group"
            href={~p"/admin/memberships"}
          />
          <.stat_card title="APIs" value={@stats.apis} icon="hero-bolt" href={~p"/admin/apis"} />
          <.stat_card title="Published APIs" value={@stats.published_apis} icon="hero-globe-alt" />
          <.stat_card
            title="Subscriptions"
            value={@stats.subscriptions}
            icon="hero-credit-card"
            href={~p"/admin/subscriptions"}
          />
        </div>

        <h2 class="text-lg font-semibold mb-4">API Data</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <.stat_card
            title="API Keys"
            value={@stats.api_keys}
            icon="hero-key"
            href={~p"/admin/api-keys"}
          />
          <.stat_card
            title="Conversations"
            value={@stats.api_conversations}
            icon="hero-chat-bubble-left-right"
            href={~p"/admin/api-conversations"}
          />
          <.stat_card
            title="Data Store"
            value={@stats.data_store_entries}
            icon="hero-circle-stack"
            href={~p"/admin/data-store-entries"}
          />
          <.stat_card
            title="Invocations"
            value={@stats.invocation_logs}
            icon="hero-arrow-path"
            href={~p"/admin/invocation-logs"}
          />
          <.stat_card
            title="Metrics"
            value={@stats.metric_rollups}
            icon="hero-chart-bar"
            href={~p"/admin/metric-rollups"}
          />
        </div>

        <h2 class="text-lg font-semibold mb-4">Billing</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <.stat_card
            title="Daily Usage"
            value={@stats.daily_usage}
            icon="hero-calendar-days"
            href={~p"/admin/daily-usage"}
          />
          <.stat_card
            title="Usage Events"
            value={@stats.usage_events}
            icon="hero-signal"
            href={~p"/admin/usage-events"}
          />
          <.stat_card
            title="Processed Events"
            value={@stats.processed_events}
            icon="hero-check-badge"
            href={~p"/admin/processed-events"}
          />
        </div>

        <h2 class="text-lg font-semibold mb-4">Testing</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <.stat_card
            title="Test Requests"
            value={@stats.test_requests}
            icon="hero-beaker"
            href={~p"/admin/test-requests"}
          />
          <.stat_card
            title="Test Suites"
            value={@stats.test_suites}
            icon="hero-clipboard-document-check"
            href={~p"/admin/test-suites"}
          />
        </div>

        <h2 class="text-lg font-semibold mb-4">LLM & Audit</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <.stat_card
            title="LLM Usage"
            value={@stats.llm_usage}
            icon="hero-cpu-chip"
            href={~p"/admin/llm-usage"}
          />
          <.stat_card
            title="Audit Logs"
            value={@stats.audit_logs}
            icon="hero-document-text"
            href={~p"/admin/audit-logs"}
          />
          <.stat_card
            title="Versions"
            value={@stats.versions}
            icon="hero-clock"
            href={~p"/admin/versions"}
          />
        </div>
      </div>
    </BlackboexWeb.Layouts.admin>
    """
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <.link :if={@href} href={@href} class="block">
      <div class="card bg-base-100 border shadow-sm hover:border-primary transition-colors cursor-pointer">
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
    </.link>
    <div :if={!@href} class="card bg-base-100 border shadow-sm">
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
      # Core
      users: Repo.aggregate(Blackboex.Accounts.User, :count),
      organizations: Repo.aggregate(Blackboex.Organizations.Organization, :count),
      memberships: Repo.aggregate(Blackboex.Organizations.Membership, :count),
      apis: Repo.aggregate(Blackboex.Apis.Api, :count),
      published_apis:
        Blackboex.Apis.Api
        |> where([a], a.status == "published")
        |> Repo.aggregate(:count),
      subscriptions: Repo.aggregate(Blackboex.Billing.Subscription, :count),
      # API data
      api_keys: Repo.aggregate(Blackboex.Apis.ApiKey, :count),
      api_conversations: Repo.aggregate(Blackboex.Apis.ApiConversation, :count),
      data_store_entries: Repo.aggregate(Blackboex.Apis.DataStore.Entry, :count),
      invocation_logs: Repo.aggregate(Blackboex.Apis.InvocationLog, :count),
      metric_rollups: Repo.aggregate(Blackboex.Apis.MetricRollup, :count),
      # Billing
      daily_usage: Repo.aggregate(Blackboex.Billing.DailyUsage, :count),
      usage_events: Repo.aggregate(Blackboex.Billing.UsageEvent, :count),
      processed_events: Repo.aggregate(Blackboex.Billing.ProcessedEvent, :count),
      # Testing
      test_requests: Repo.aggregate(Blackboex.Testing.TestRequest, :count),
      test_suites: Repo.aggregate(Blackboex.Testing.TestSuite, :count),
      # LLM & Audit
      llm_usage: Repo.aggregate(Blackboex.LLM.Usage, :count),
      audit_logs: Repo.aggregate(Blackboex.Audit.AuditLog, :count),
      versions: Repo.aggregate(Blackboex.Audit.Version, :count)
    }
  end
end
