defmodule BlackboexWeb.ApiKeyLive.Show do
  @moduledoc """
  LiveView for viewing API key details, metrics, and performing key actions (rotate, revoke).
  """
  use BlackboexWeb, :live_view

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
      <div class="flex items-center justify-between">
        <div>
          <div class="flex items-center gap-3">
            <.link navigate={~p"/api-keys"} class="text-muted-foreground hover:text-foreground">
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <h1 class="text-2xl font-bold tracking-tight font-mono">{@key.key_prefix}...</h1>
            <span class={[
              "inline-flex rounded-full px-2 py-0.5 text-xs font-semibold",
              status_class(@key)
            ]}>
              {status_label(@key)}
            </span>
          </div>
          <p class="text-muted-foreground mt-1">
            {@key.label || "Unnamed key"} · API:
            <%= if @key.api do %>
              <.link navigate={~p"/apis/#{@key.api_id}"} class="text-primary hover:underline">
                {@key.api.name}
              </.link>
            <% else %>
              <span>Unknown</span>
            <% end %>
          </p>
        </div>

        <div class="flex gap-2">
          <button
            :if={!@key.revoked_at}
            phx-click="rotate"
            class="inline-flex items-center rounded-md border px-3 py-2 text-sm hover:bg-accent"
          >
            <.icon name="hero-arrow-path" class="mr-1.5 size-4" /> Rotate
          </button>
          <button
            :if={!@key.revoked_at}
            phx-click="revoke"
            data-confirm="Revoke this key? API calls using it will immediately fail."
            class="inline-flex items-center rounded-md border border-destructive px-3 py-2 text-sm text-destructive hover:bg-destructive/10"
          >
            <.icon name="hero-x-circle" class="mr-1.5 size-4" /> Revoke
          </button>
        </div>
      </div>

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
            <button
              :for={p <- ~w(24h 7d 30d)}
              phx-click="set_period"
              phx-value-period={p}
              class={[
                "rounded px-3 py-1 text-xs font-medium transition-colors",
                if(p == @period,
                  do: "bg-primary text-primary-foreground",
                  else: "hover:bg-accent"
                )
              ]}
            >
              {p}
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <.stat_card label="Total Requests" value={@metrics.total_requests} />
          <.stat_card
            label="Errors"
            value={@metrics.errors}
            color={if @metrics.errors > 0, do: "red"}
          />
          <.stat_card label="Avg Latency" value={format_latency(@metrics.avg_latency)} />
          <.stat_card label="Success Rate" value={"#{@metrics.success_rate}%"} />
        </div>
      </div>

      <%!-- Details --%>
      <div class="rounded-lg border bg-card p-6 shadow-sm space-y-4">
        <h2 class="text-lg font-semibold">Details</h2>
        <dl class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
          <div>
            <dt class="font-medium text-muted-foreground">Key Prefix</dt>
            <dd class="font-mono mt-1">{@key.key_prefix}</dd>
          </div>
          <div>
            <dt class="font-medium text-muted-foreground">Label</dt>
            <dd class="mt-1">{@key.label || "—"}</dd>
          </div>
          <div>
            <dt class="font-medium text-muted-foreground">Created</dt>
            <dd class="mt-1">
              {Calendar.strftime(@key.inserted_at, "%B %d, %Y at %H:%M UTC")}
            </dd>
          </div>
          <div>
            <dt class="font-medium text-muted-foreground">Last Used</dt>
            <dd class="mt-1">{format_last_used(@key.last_used_at)}</dd>
          </div>
          <div>
            <dt class="font-medium text-muted-foreground">Expires</dt>
            <dd class="mt-1">
              {if @key.expires_at,
                do: Calendar.strftime(@key.expires_at, "%B %d, %Y"),
                else: "Never"}
            </dd>
          </div>
          <div>
            <dt class="font-medium text-muted-foreground">Rate Limit</dt>
            <dd class="mt-1">
              {if @key.rate_limit, do: "#{@key.rate_limit} req/min", else: "Default"}
            </dd>
          </div>
          <%= if @key.revoked_at do %>
            <div>
              <dt class="font-medium text-muted-foreground">Revoked At</dt>
              <dd class="mt-1 text-destructive">
                {Calendar.strftime(@key.revoked_at, "%B %d, %Y at %H:%M UTC")}
              </dd>
            </div>
          <% end %>
        </dl>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card p-4 shadow-sm">
      <p class="text-xs font-medium text-muted-foreground">{@label}</p>
      <p class={["text-2xl font-bold mt-1", @color == "red" && "text-destructive"]}>
        {@value}
      </p>
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

  defp status_class(key), do: api_key_status_classes(status_label(key))

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
