defmodule BlackboexWeb.ApiKeyLive.Show do
  @moduledoc """
  LiveView for viewing API key details, metrics, and performing key actions (rotate, revoke).
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DescriptionList

  alias Blackboex.Apis.Keys

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.current_scope.organization
    key = Keys.get_key(id)

    if key && key.organization_id == org.id do
      metrics = Keys.key_metrics(key.id, :week)

      {:ok,
       assign(socket,
         page_title: "Key: #{key.key_prefix}...",
         key: key,
         metrics: metrics,
         period: "7d",
         plain_key_flash: nil
       )}
    else
      {:ok, socket |> put_flash(:error, "Key not found") |> push_navigate(to: ~p"/api-keys")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <.header>
        <div class="flex items-center gap-3">
          <.link navigate={~p"/api-keys"} class="text-muted-foreground hover:text-foreground">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <span class="text-2xl font-bold tracking-tight font-mono">{@key.key_prefix}...</span>
          <.badge class={api_key_status_classes(status_label(@key))}>
            {status_label(@key)}
          </.badge>
        </div>
        <:subtitle>
          {@key.label || "Unnamed key"} · API:
          <%= if @key.api do %>
            <.link navigate={~p"/apis/#{@key.api_id}"} class="text-primary hover:underline">
              {@key.api.name}
            </.link>
          <% else %>
            <span>Unknown</span>
          <% end %>
        </:subtitle>
        <:actions>
          <div class="flex gap-2">
            <.button
              :if={!@key.revoked_at}
              phx-click="rotate"
              variant="default"
              size="sm"
            >
              <.icon name="hero-arrow-path" class="mr-1.5 size-4" /> Rotate
            </.button>
            <.button
              :if={!@key.revoked_at}
              phx-click="revoke"
              data-confirm="Revoke this key? API calls using it will immediately fail."
              variant="destructive"
              size="sm"
            >
              <.icon name="hero-x-circle" class="mr-1.5 size-4" /> Revoke
            </.button>
          </div>
        </:actions>
      </.header>

      <%!-- Plain key flash --%>
      <%= if @plain_key_flash do %>
        <div class="rounded-lg border-2 border-primary bg-muted p-4 space-y-2">
          <p class="font-semibold text-foreground">New key — copy now:</p>
          <code class="block bg-accent text-accent-foreground p-2 rounded font-mono text-sm break-all select-all">
            {@plain_key_flash}
          </code>
          <button phx-click="dismiss_flash" class="text-primary hover:underline text-xs">
            Dismiss
          </button>
        </div>
      <% end %>

      <%!-- Metrics --%>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Usage</h2>
          <div class="flex gap-1 rounded-lg border p-0.5">
            <.button
              :for={p <- ~w(24h 7d 30d)}
              phx-click="set_period"
              phx-value-period={p}
              variant={if p == @period, do: "primary", else: "ghost"}
              size="sm"
            >
              {p}
            </.button>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <.stat_card label="Total Requests" value={@metrics.total_requests} />
          <.stat_card
            label="Errors"
            value={@metrics.errors}
            color={if @metrics.errors > 0, do: "destructive"}
          />
          <.stat_card label="Avg Latency" value={format_latency(@metrics.avg_latency)} />
          <.stat_card label="Success Rate" value={"#{@metrics.success_rate}%"} />
        </div>
      </div>

      <%!-- Details --%>
      <.card>
        <.card_content class="pt-6">
          <h2 class="text-lg font-semibold mb-4">Details</h2>
          <.description_list>
            <:item label="Key Prefix">
              <span class="font-mono">{@key.key_prefix}</span>
            </:item>
            <:item label="Label">{@key.label || "—"}</:item>
            <:item label="Created">
              {Calendar.strftime(@key.inserted_at, "%B %d, %Y at %H:%M UTC")}
            </:item>
            <:item label="Last Used">{format_last_used(@key.last_used_at)}</:item>
            <:item label="Expires">
              {if @key.expires_at,
                do: Calendar.strftime(@key.expires_at, "%B %d, %Y"),
                else: "Never"}
            </:item>
            <:item label="Rate Limit">
              {if @key.rate_limit, do: "#{@key.rate_limit} req/min", else: "Default"}
            </:item>
            <:item :if={@key.revoked_at} label="Revoked At">
              <span class="text-destructive">
                {Calendar.strftime(@key.revoked_at, "%B %d, %Y at %H:%M UTC")}
              </span>
            </:item>
          </.description_list>
        </.card_content>
      </.card>
    </div>
    """
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    atom_period =
      case period do
        "24h" -> :day
        "7d" -> :week
        "30d" -> :month
        _ -> :week
      end

    metrics = Keys.key_metrics(socket.assigns.key.id, atom_period)
    {:noreply, assign(socket, metrics: metrics, period: period)}
  end

  @impl true
  def handle_event("revoke", _params, socket) do
    case Keys.revoke_key(socket.assigns.key) do
      {:ok, revoked_key} ->
        {:noreply,
         socket
         |> assign(key: %{revoked_key | api: socket.assigns.key.api})
         |> put_flash(:info, "Key revoked")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke key")}
    end
  end

  @impl true
  def handle_event("rotate", _params, socket) do
    case Keys.rotate_key(socket.assigns.key) do
      {:ok, plain_key, new_key} ->
        new_key = Keys.get_key(new_key.id)
        {:noreply, assign(socket, key: new_key, plain_key_flash: plain_key)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to rotate key")}
    end
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, plain_key_flash: nil)}
  end

  defp status_label(%{revoked_at: r}) when not is_nil(r), do: "Revoked"

  defp status_label(%{expires_at: e}) when not is_nil(e) do
    if DateTime.compare(e, DateTime.utc_now()) == :lt, do: "Expired", else: "Active"
  end

  defp status_label(_), do: "Active"

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  defp format_latency(ms), do: "#{ms}ms"

  defp format_last_used(nil), do: "Never"

  defp format_last_used(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      true -> Calendar.strftime(dt, "%B %d, %Y")
    end
  end
end
