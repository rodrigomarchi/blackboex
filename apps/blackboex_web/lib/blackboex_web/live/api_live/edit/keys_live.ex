defmodule BlackboexWeb.ApiLive.Edit.KeysLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [time_ago: 1]

  alias Blackboex.Apis.Keys
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  # ── Mount ─────────────────────────────────────────────────────────────

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, socket |> init_assigns() |> load_keys()}
      {:error, socket} -> {:ok, socket}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="keys">
      <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-semibold">API Keys</h2>
          <button
            phx-click="create_key"
            class="inline-flex items-center rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
          >
            <.icon name="hero-plus" class="size-3 mr-1" /> Create Key
          </button>
        </div>

        <%= if @plain_key_flash do %>
          <div class="rounded-lg border-2 border-warning bg-warning/10 p-4 space-y-2">
            <p class="text-sm font-semibold text-warning-foreground">
              Copy this key now — it won't be shown again
            </p>
            <div class="flex items-center gap-2">
              <code class="flex-1 rounded bg-background p-2 font-mono text-xs break-all select-all border">
                {@plain_key_flash}
              </code>
              <button
                phx-click="copy_key"
                class="shrink-0 rounded border px-2 py-1 text-xs hover:bg-accent"
              >
                Copy
              </button>
            </div>
            <button
              phx-click="dismiss_key_flash"
              class="text-xs text-muted-foreground hover:underline"
            >
              Dismiss
            </button>
          </div>
        <% end %>

        <%= if @api_keys == [] do %>
          <div class="rounded-lg border border-dashed p-8 text-center">
            <.icon name="hero-key" class="size-8 mx-auto text-muted-foreground mb-3" />
            <p class="text-sm font-medium">No API keys yet</p>
            <p class="text-xs text-muted-foreground mt-1">
              Keys are required to call published APIs. Create one to get started.
            </p>
          </div>
        <% else %>
          <div class="space-y-3">
            <div :for={key <- @api_keys} class="rounded-lg border p-4 space-y-3">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <code class="font-mono text-sm">{key.key_prefix}...</code>
                  <span class={[
                    "inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold",
                    if(key.revoked_at,
                      do: api_key_status_classes("Revoked"),
                      else: api_key_status_classes("Active")
                    )
                  ]}>
                    {if key.revoked_at, do: "Revoked", else: "Active"}
                  </span>
                  <span :if={key.label} class="text-xs text-muted-foreground">{key.label}</span>
                </div>
                <div :if={!key.revoked_at} class="flex items-center gap-2">
                  <button
                    phx-click="rotate_key"
                    phx-value-key-id={key.id}
                    data-confirm="Rotate this key? The old key will be revoked immediately."
                    class="rounded border px-2 py-1 text-xs hover:bg-accent"
                  >
                    Rotate
                  </button>
                  <button
                    phx-click="revoke_key"
                    phx-value-key-id={key.id}
                    data-confirm="Revoke this key? This cannot be undone."
                    class="rounded border border-destructive/50 px-2 py-1 text-xs text-destructive hover:bg-destructive/10"
                  >
                    Revoke
                  </button>
                </div>
              </div>

              <div class="grid grid-cols-3 gap-4 text-xs text-muted-foreground">
                <div>
                  <span class="block text-[10px] uppercase tracking-wide">Created</span>
                  {Calendar.strftime(key.inserted_at, "%Y-%m-%d")}
                </div>
                <div>
                  <span class="block text-[10px] uppercase tracking-wide">Last used</span>
                  {if key.last_used_at, do: time_ago(key.last_used_at), else: "never"}
                </div>
                <div>
                  <span class="block text-[10px] uppercase tracking-wide">
                    {if key.revoked_at, do: "Revoked", else: "Expires"}
                  </span>
                  {cond do
                    key.revoked_at -> Calendar.strftime(key.revoked_at, "%Y-%m-%d")
                    key.expires_at -> Calendar.strftime(key.expires_at, "%Y-%m-%d")
                    true -> "never"
                  end}
                </div>
              </div>

              <%= if !key.revoked_at && key.metrics do %>
                <div class="grid grid-cols-4 gap-2">
                  <div class="rounded border p-2 text-center">
                    <p class="text-sm font-bold">{key.metrics.total_requests}</p>
                    <p class="text-[10px] text-muted-foreground">Requests</p>
                  </div>
                  <div class="rounded border p-2 text-center">
                    <p class="text-sm font-bold">{key.metrics.success_rate}%</p>
                    <p class="text-[10px] text-muted-foreground">Success</p>
                  </div>
                  <div class="rounded border p-2 text-center">
                    <p class="text-sm font-bold">{key.metrics.avg_latency}ms</p>
                    <p class="text-[10px] text-muted-foreground">Latency</p>
                  </div>
                  <div class="rounded border p-2 text-center">
                    <p class="text-sm font-bold">{key.metrics.errors}</p>
                    <p class="text-[10px] text-muted-foreground">Errors</p>
                  </div>
                </div>
                <p class="text-[10px] text-muted-foreground">Last 7 days</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </.editor_shell>
    """
  end

  # ── handle_event: command palette ────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── handle_event: keys tab ────────────────────────────────────────────

  @impl true
  def handle_event("create_key", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Keys.create_key(api, %{label: "API Key", organization_id: org.id}) do
      {:ok, plain_key, _api_key} ->
        keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
        {:noreply, assign(socket, api_keys: keys, plain_key_flash: plain_key)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create key")}
    end
  end

  @impl true
  def handle_event("revoke_key", %{"key-id" => key_id}, socket) do
    %{api: api, api_keys: api_keys} = socket.assigns
    key = Enum.find(api_keys, &(&1.id == key_id and &1.api_id == api.id))

    if key do
      case Keys.revoke_key(key) do
        {:ok, _} ->
          keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
          {:noreply, assign(socket, api_keys: keys)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to revoke key")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rotate_key", %{"key-id" => key_id}, socket) do
    %{api: api, api_keys: api_keys} = socket.assigns
    key = Enum.find(api_keys, &(&1.id == key_id and &1.api_id == api.id))

    if key do
      case Keys.rotate_key(key) do
        {:ok, plain_key, _new_key} ->
          keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
          {:noreply, assign(socket, api_keys: keys, plain_key_flash: plain_key)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to rotate key")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_key_flash", _params, socket) do
    {:noreply, assign(socket, plain_key_flash: nil)}
  end

  @impl true
  def handle_event("copy_key", _params, socket) do
    if socket.assigns.plain_key_flash do
      {:noreply, push_event(socket, "copy_to_clipboard", %{text: socket.assigns.plain_key_flash})}
    else
      {:noreply, socket}
    end
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp init_assigns(socket) do
    assign(socket,
      api_keys: [],
      keys_loaded: false,
      plain_key_flash: nil
    )
  end

  defp load_keys(socket) do
    keys = enrich_keys_with_metrics(Keys.list_keys(socket.assigns.api.id))
    assign(socket, api_keys: keys, keys_loaded: true)
  end

  defp enrich_keys_with_metrics(keys) do
    Enum.map(keys, fn key ->
      if key.revoked_at do
        Map.put(key, :metrics, nil)
      else
        Map.put(key, :metrics, Keys.key_metrics(key.id))
      end
    end)
  end

  defp shared_shell_assigns(assigns) do
    Map.take(assigns, [
      :api,
      :versions,
      :selected_version,
      :generation_status,
      :validation_report,
      :test_summary,
      :command_palette_open,
      :command_palette_query,
      :command_palette_selected
    ])
  end
end
