defmodule BlackboexWeb.ApiKeyLive.Index do
  @moduledoc """
  LiveView for listing and creating API keys across all organization APIs.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys
  alias Blackboex.Policy

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
      <.header>
        API Keys
        <:subtitle>Manage authentication keys across all your APIs</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="toggle_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4" /> New Key
          </.button>
        </:actions>
      </.header>

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
      <%= if @keys == [] do %>
        <.empty_state
          icon="hero-key"
          title="No API keys yet"
          description="Create a key to authenticate API requests"
        />
      <% else %>
        <.table id="keys" rows={@keys}>
          <:col :let={key} label="Key">
            <span class="font-mono text-xs">{key.key_prefix}...</span>
          </:col>
          <:col :let={key} label="Label">{key.label || "—"}</:col>
          <:col :let={key} label="API">
            <%= if key.api do %>
              <.link navigate={~p"/apis/#{key.api_id}"} class="text-primary hover:underline">
                {key.api.name}
              </.link>
            <% else %>
              <span class="text-muted-foreground">—</span>
            <% end %>
          </:col>
          <:col :let={key} label="Status">
            <.badge class={api_key_status_classes(key_status(key))}>
              {key_status(key)}
            </.badge>
          </:col>
          <:col :let={key} label="Created">
            <span class="text-muted-foreground text-xs">{format_date(key.inserted_at)}</span>
          </:col>
          <:col :let={key} label="Last Used">
            <span class="text-muted-foreground text-xs">{format_last_used(key.last_used_at)}</span>
          </:col>
          <:action :let={key}>
            <.link navigate={~p"/api-keys/#{key.id}"} class="text-xs text-primary hover:underline">
              Details
            </.link>
          </:action>
        </.table>
      <% end %>

      <%!-- Create Modal --%>
      <.modal show={@show_create_modal} on_close="toggle_create_modal" title="Create API Key">
        <form phx-submit="create_key" class="space-y-4">
          <.input
            type="select"
            name="api_id"
            label="API"
            required
            prompt="Select an API..."
            options={Enum.map(@apis, &{"#{&1.name} (#{&1.slug})", &1.id})}
            value={nil}
          />
          <.input
            type="text"
            name="label"
            label="Label"
            value="API Key"
            maxlength="200"
          />
          <div class="flex justify-end gap-2">
            <.button type="button" variant="outline" phx-click="toggle_create_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary">
              Create Key
            </.button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: !socket.assigns.show_create_modal)}
  end

  @impl true
  def handle_event("create_key", %{"api_id" => api_id, "label" => label}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:api_key_create, scope, org),
         api when not is_nil(api) <- Apis.get_api(org.id, api_id) do
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
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
      nil -> {:noreply, put_flash(socket, :error, "API not found")}
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
