defmodule BlackboexWeb.ApiKeyLive.Index do
  @moduledoc """
  LiveView for listing and creating API keys across all organization APIs.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    keys = Keys.list_org_keys(org.id)
    apis = Apis.list_apis(org.id)

    {:ok,
     assign(socket,
       page_title: "API Keys",
       keys: keys,
       apis: apis,
       show_create_modal: false,
       plain_key_flash: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">API Keys</h1>
          <p class="text-muted-foreground">Manage authentication keys across all your APIs</p>
        </div>
        <button
          phx-click="toggle_create_modal"
          class="inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> New Key
        </button>
      </div>

      <%!-- Plain key flash (shown after create/rotate) --%>
      <%= if @plain_key_flash do %>
        <div class="rounded-lg border-2 border-primary bg-muted p-4 space-y-2">
          <p class="font-semibold text-foreground">
            Copy this key now — it won't be shown again:
          </p>
          <code class="block bg-accent text-accent-foreground p-2 rounded font-mono text-sm break-all select-all">
            {@plain_key_flash}
          </code>
          <button phx-click="dismiss_flash" class="text-primary hover:underline text-xs">
            Dismiss
          </button>
        </div>
      <% end %>

      <%!-- Keys table --%>
      <div class="rounded-lg border bg-card shadow-sm">
        <%= if @keys == [] do %>
          <div class="p-8 text-center text-muted-foreground">
            <.icon name="hero-key" class="mx-auto size-12 mb-4 opacity-50" />
            <p class="text-lg font-medium">No API keys yet</p>
            <p class="text-sm">Create a key to authenticate API requests</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b bg-muted/50">
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">Key</th>
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">Label</th>
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">API</th>
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">Created</th>
                  <th class="px-4 py-3 text-left font-medium text-muted-foreground">Last Used</th>
                  <th class="px-4 py-3 text-right font-medium text-muted-foreground">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={key <- @keys} class="border-b last:border-0 hover:bg-muted/30">
                  <td class="px-4 py-3 font-mono text-xs">{key.key_prefix}...</td>
                  <td class="px-4 py-3">{key.label || "—"}</td>
                  <td class="px-4 py-3">
                    <%= if key.api do %>
                      <.link
                        navigate={~p"/apis/#{key.api_id}"}
                        class="text-primary hover:underline"
                      >
                        {key.api.name}
                      </.link>
                    <% else %>
                      <span class="text-muted-foreground">—</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3">
                    <span class={[
                      "inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold",
                      key_status_class(key)
                    ]}>
                      {key_status(key)}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-muted-foreground text-xs">
                    {format_date(key.inserted_at)}
                  </td>
                  <td class="px-4 py-3 text-muted-foreground text-xs">
                    {format_last_used(key.last_used_at)}
                  </td>
                  <td class="px-4 py-3 text-right">
                    <.link
                      navigate={~p"/api-keys/#{key.id}"}
                      class="text-xs text-primary hover:underline"
                    >
                      Details
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <%!-- Create Modal --%>
      <%= if @show_create_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center">
          <div class="fixed inset-0 bg-black/50" phx-click="toggle_create_modal" />
          <div class="modal-panel relative z-10 w-full max-w-md rounded-lg border p-6 shadow-xl">
            <h2 class="text-lg font-semibold mb-4">Create API Key</h2>
            <form phx-submit="create_key" class="space-y-4">
              <div>
                <label class="text-sm font-medium">API</label>
                <select
                  name="api_id"
                  required
                  class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                >
                  <option value="">Select an API...</option>
                  <%= for api <- @apis do %>
                    <option value={api.id}>{api.name} ({api.slug})</option>
                  <% end %>
                </select>
              </div>
              <div>
                <label class="text-sm font-medium">Label</label>
                <input
                  type="text"
                  name="label"
                  value="API Key"
                  maxlength="200"
                  class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                />
              </div>
              <div class="flex justify-end gap-2">
                <button
                  type="button"
                  phx-click="toggle_create_modal"
                  class="rounded-md border px-4 py-2 text-sm hover:bg-accent"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
                >
                  Create Key
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: !socket.assigns.show_create_modal)}
  end

  @impl true
  def handle_event("create_key", %{"api_id" => api_id, "label" => label}, socket) do
    org = socket.assigns.current_scope.organization
    api = Apis.get_api(org.id, api_id)

    if api do
      case Keys.create_key(api, %{label: label, organization_id: org.id}) do
        {:ok, plain_key, _api_key} ->
          keys = Keys.list_org_keys(org.id)

          {:noreply,
           assign(socket,
             keys: keys,
             plain_key_flash: plain_key,
             show_create_modal: false
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create key")}
      end
    else
      {:noreply, put_flash(socket, :error, "API not found")}
    end
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, plain_key_flash: nil)}
  end

  # Helpers

  defp key_status(%{revoked_at: revoked}) when not is_nil(revoked), do: "Revoked"

  defp key_status(%{expires_at: exp}) when not is_nil(exp) do
    if DateTime.compare(exp, DateTime.utc_now()) == :lt, do: "Expired", else: "Active"
  end

  defp key_status(_), do: "Active"

  defp key_status_class(key) do
    case key_status(key) do
      "Active" -> "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
      "Revoked" -> "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300"
      "Expired" -> "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400"
    end
  end

  defp format_date(nil), do: "—"

  defp format_date(dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  defp format_last_used(nil), do: "Never"

  defp format_last_used(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
