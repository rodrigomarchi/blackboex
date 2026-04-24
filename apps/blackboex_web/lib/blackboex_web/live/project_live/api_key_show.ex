defmodule BlackboexWeb.ProjectLive.ApiKeyShow do
  @moduledoc """
  Project-scoped LiveView for viewing API key details, metrics, and
  performing key actions (rotate, revoke).
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DescriptionList
  import BlackboexWeb.Components.Shared.DashboardHelpers, only: [format_latency: 1]
  import BlackboexWeb.Components.Shared.PlainKeyBanner
  import BlackboexWeb.Components.UI.SectionHeading

  alias Blackboex.Apis.Keys
  alias Blackboex.Policy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    project = scope.project
    key = Keys.get_key(id)

    cond do
      is_nil(key) ->
        {:ok,
         socket
         |> put_flash(:error, "Key not found")
         |> push_navigate(to: keys_index_path(org, project))}

      key.organization_id != org.id or key.project_id != project.id ->
        {:ok,
         socket
         |> put_flash(:error, "Key not found")
         |> push_navigate(to: keys_index_path(org, project))}

      true ->
        metrics = Keys.key_metrics(key.id, :week)

        {:ok,
         assign(socket,
           page_title: "Key: #{key.key_prefix}...",
           org: org,
           project: project,
           key: key,
           metrics: metrics,
           period: "7d",
           plain_key_flash: nil,
           confirm: nil
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <div class="flex items-center gap-3">
          <.link navigate={keys_index_path(@org, @project)} class="link-muted">
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
            <.link
              navigate={~p"/orgs/#{@org.slug}/projects/#{@project.slug}/apis/#{@key.api.slug}"}
              class="link-entity"
            >
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
              <.icon name="hero-arrow-path" class="mr-1.5 size-4 text-accent-amber" /> Rotate
            </.button>
            <.button
              :if={!@key.revoked_at}
              phx-click="request_confirm"
              phx-value-action="revoke"
              variant="destructive"
              size="sm"
            >
              <.icon name="hero-x-circle" class="mr-1.5 size-4 text-accent-red" /> Revoke
            </.button>
          </div>
        </:actions>
      </.header>

      <.plain_key_banner :if={@plain_key_flash} plain_key={@plain_key_flash} />

      <.page_section>
        <div class="flex items-center justify-between">
          <.section_heading
            icon="hero-chart-bar"
            icon_class="size-4 text-accent-sky"
            level="h1"
          >
            Usage
          </.section_heading>
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

        <.stat_grid cols="4">
          <.stat_card label="Total Requests" value={@metrics.total_requests} />
          <.stat_card
            label="Errors"
            value={@metrics.errors}
            color={if @metrics.errors > 0, do: "destructive"}
          />
          <.stat_card label="Avg Latency" value={format_latency(@metrics.avg_latency)} />
          <.stat_card label="Success Rate" value={"#{@metrics.success_rate}%"} />
        </.stat_grid>
      </.page_section>

      <.card>
        <.card_content standalone>
          <.section_heading
            icon="hero-information-circle"
            icon_class="size-4 text-accent-blue"
            class="mb-4"
            level="h1"
          >
            Details
          </.section_heading>
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
    </.page>
    """
  end

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = build_confirm(params["action"], params)
    {:noreply, assign(socket, confirm: confirm)}
  end

  @impl true
  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end

  @impl true
  def handle_event("execute_confirm", _params, socket) do
    case socket.assigns.confirm do
      nil ->
        {:noreply, socket}

      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
    end
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
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:api_key_revoke, scope, org) do
      case Keys.revoke_key(socket.assigns.key) do
        {:ok, revoked_key} ->
          {:noreply,
           socket
           |> assign(key: %{revoked_key | api: socket.assigns.key.api})
           |> put_flash(:info, "Key revoked")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to revoke key")}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  @impl true
  def handle_event("rotate", _params, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:api_key_rotate, scope, org) do
      case Keys.rotate_key(socket.assigns.key) do
        {:ok, plain_key, new_key} ->
          new_key = Keys.get_key(new_key.id)
          {:noreply, assign(socket, key: new_key, plain_key_flash: plain_key)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to rotate key")}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, plain_key_flash: nil)}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp keys_index_path(org, project),
    do: "/orgs/#{org.slug}/projects/#{project.slug}/api-keys"

  defp build_confirm("revoke", _params) do
    %{
      title: "Revoke this API key?",
      description:
        "The key will be immediately revoked and can no longer be used to authenticate requests. This cannot be undone.",
      variant: :danger,
      confirm_label: "Revoke",
      event: "revoke",
      meta: %{}
    }
  end

  defp build_confirm(_, _), do: nil

  defp status_label(%{revoked_at: r}) when not is_nil(r), do: "Revoked"

  defp status_label(%{expires_at: e}) when not is_nil(e) do
    if DateTime.compare(e, DateTime.utc_now()) == :lt, do: "Expired", else: "Active"
  end

  defp status_label(_), do: "Active"

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
