defmodule BlackboexWeb.ProjectLive.ApiKeys do
  @moduledoc """
  Project-scoped LiveView for listing and creating API keys.

  Replaces the former org-wide `ApiKeyLive.Index`. Access is enforced by
  the `SetProjectFromUrl` on_mount hook — any user that cannot reach the
  project URL is redirected to login. Mutations go through
  `Policy.authorize_and_track/3`.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.PlainKeyBanner
  import BlackboexWeb.Components.Shared.ProjectSettingsTabs

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys
  alias Blackboex.Policy

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    project = scope.project

    {keys, apis} =
      if project do
        {Keys.list_keys_for_project(project.id), Apis.list_for_project(project.id)}
      else
        {[], []}
      end

    {:ok,
     assign(socket,
       page_title: "API Keys",
       org: org,
       project: project,
       keys: keys,
       apis: apis,
       show_create_modal: false,
       plain_key_flash: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-key" class="size-5 text-accent-amber" /> API Keys
        </span>
        <:subtitle>
          Manage authentication keys for APIs in
          <span class="font-medium">{@project && @project.name}</span>
        </:subtitle>
        <:actions>
          <.button variant="primary" phx-click="toggle_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4 text-accent-emerald" /> New Key
          </.button>
        </:actions>
      </.header>

      <.project_settings_tabs
        :if={@project}
        active={:api_keys}
        org_slug={@org.slug}
        project_slug={@project.slug}
      />

      <.plain_key_banner :if={@plain_key_flash} plain_key={@plain_key_flash} />

      <%= if @keys == [] do %>
        <.empty_state
          icon="hero-key"
          icon_class="text-accent-amber"
          title="No API keys yet"
          description="Create a key to authenticate API requests for this project"
        />
      <% else %>
        <.table id="keys" rows={@keys}>
          <:col :let={key} label="Key">
            <span class="font-mono text-xs">{key.key_prefix}...</span>
          </:col>
          <:col :let={key} label="Label">{key.label || "—"}</:col>
          <:col :let={key} label="API">
            <%= if key.api do %>
              <.link
                navigate={~p"/orgs/#{@org.slug}/projects/#{@project.slug}/apis/#{key.api.slug}"}
                class="link-entity"
              >
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
            <.link
              navigate={~p"/orgs/#{@org.slug}/projects/#{@project.slug}/api-keys/#{key.id}"}
              class="inline-flex items-center link-primary"
            >
              <.icon name="hero-eye-mini" class="mr-1 size-3" /> Details
            </.link>
          </:action>
        </.table>
      <% end %>

      <.modal show={@show_create_modal} on_close="toggle_create_modal" title="Create API Key">
        <.form :let={_f} for={%{}} as={:key} phx-submit="create_key" class="space-y-4">
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
          <.form_actions spacing="tight">
            <.button type="button" variant="outline" phx-click="toggle_create_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary">
              <.icon name="hero-key" class="mr-1.5 size-3.5 text-accent-amber" /> Create Key
            </.button>
          </.form_actions>
        </.form>
      </.modal>
    </.page>
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
    project = scope.project

    with :ok <- Policy.authorize_and_track(:api_key_create, scope, org),
         api when not is_nil(api) <- Apis.get_api(org.id, api_id),
         true <- api.project_id == project.id do
      case Keys.create_key(api, %{
             label: label,
             organization_id: org.id,
             project_id: project.id
           }) do
        {:ok, plain_key, _api_key} ->
          keys = Keys.list_keys_for_project(project.id)

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
      false -> {:noreply, put_flash(socket, :error, "API does not belong to this project")}
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
