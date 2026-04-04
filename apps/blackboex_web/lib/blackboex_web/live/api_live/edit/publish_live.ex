defmodule BlackboexWeb.ApiLive.Edit.PublishLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, socket |> init_assigns()}
      {:error, socket} -> {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="publish">
      <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-6">
        <h2 class="text-sm font-semibold">Publication</h2>

        <%!-- Status card --%>
        <div class="rounded-lg border p-4 space-y-2">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-xs text-muted-foreground">Status</span>
              <span class={[
                "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
                api_status_border(@api.status)
              ]}>
                {@api.status}
              </span>
            </div>
            <%= if @api.status == "compiled" do %>
              <button
                phx-click="publish"
                class="rounded-md bg-info px-3 py-1.5 text-xs font-medium text-info-foreground hover:bg-info/90"
              >
                Publish API
              </button>
            <% end %>
            <%= if @api.status == "published" do %>
              <button
                phx-click="unpublish"
                data-confirm="Unpublish this API? It will no longer be accessible."
                class="rounded-md border border-destructive px-3 py-1.5 text-xs font-medium text-destructive hover:bg-destructive/10"
              >
                Unpublish
              </button>
            <% end %>
          </div>
          <div class="flex items-center gap-2 text-xs">
            <span class="text-muted-foreground">URL</span>
            <code class="font-mono">/api/{@org.slug}/{@api.slug}</code>
            <button
              phx-click="copy_url"
              class="text-primary hover:underline text-[10px]"
            >
              Copy
            </button>
            <%= if @api.status == "draft" do %>
              <span class="text-muted-foreground">(preview)</span>
            <% end %>
          </div>
        </div>

        <%= if @api.status == "draft" do %>
          <p class="text-sm text-muted-foreground">
            Save the API to compile it. Once compiled, you can publish.
          </p>
        <% end %>

        <%= if @api.status == "compiled" do %>
          <p class="text-sm text-muted-foreground">
            Ready to publish. A default API key will be created automatically.
          </p>
        <% end %>

        <%!-- Metrics --%>
        <%= if @api.status == "published" && @metrics do %>
          <div>
            <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Metrics (24h)</h3>
            <div class="grid grid-cols-4 gap-3">
              <div class="rounded-lg border p-3 text-center">
                <p class="text-xl font-bold">{@metrics.count_24h}</p>
                <p class="text-[10px] text-muted-foreground">Total Calls</p>
              </div>
              <div class="rounded-lg border p-3 text-center">
                <p class="text-xl font-bold">{@metrics.success_rate}%</p>
                <p class="text-[10px] text-muted-foreground">Success Rate</p>
              </div>
              <div class="rounded-lg border p-3 text-center">
                <p class="text-xl font-bold">{@metrics.avg_latency}ms</p>
                <p class="text-[10px] text-muted-foreground">Avg Latency</p>
              </div>
              <div class="rounded-lg border p-3 text-center">
                <p class="text-xl font-bold">{@metrics[:error_count] || 0}</p>
                <p class="text-[10px] text-muted-foreground">Errors</p>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Documentation --%>
        <%= if @api.status in ["compiled", "published"] do %>
          <div>
            <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Documentation</h3>
            <div class="space-y-2">
              <div class="flex items-center justify-between rounded border p-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-document-text" class="size-4 text-muted-foreground" />
                  <span class="text-sm">Swagger UI</span>
                </div>
                <a
                  href={"/api/#{@org.slug}/#{@api.slug}/docs"}
                  target="_blank"
                  class="text-xs text-primary hover:underline"
                >
                  Open
                </a>
              </div>
              <div class="flex items-center justify-between rounded border p-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-code-bracket" class="size-4 text-muted-foreground" />
                  <span class="text-sm">OpenAPI JSON</span>
                </div>
                <a
                  href={"/api/#{@org.slug}/#{@api.slug}/openapi.json"}
                  target="_blank"
                  class="text-xs text-primary hover:underline"
                >
                  Open
                </a>
              </div>
              <div class="flex items-center justify-between rounded border p-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-document-check" class="size-4 text-muted-foreground" />
                  <span class="text-sm">Markdown Docs</span>
                  <%= if @api.documentation_md do %>
                    <span class="text-[10px] text-success-foreground font-medium">
                      Auto-generated
                    </span>
                  <% else %>
                    <span class="text-[10px] text-muted-foreground">Generated on save</span>
                  <% end %>
                </div>
                <.link
                  :if={@api.documentation_md}
                  patch={~p"/apis/#{@api.id}/edit/docs"}
                  class="text-xs text-primary hover:underline"
                >
                  View
                </.link>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Settings --%>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Settings</h3>
          <form phx-submit="save_publish_settings" class="space-y-3">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-xs font-medium">HTTP Method</label>
                <select
                  name="method"
                  class="mt-1 w-full rounded-md border bg-background px-3 py-1.5 text-sm"
                >
                  <option
                    :for={m <- ~w(GET POST PUT PATCH DELETE)}
                    value={m}
                    selected={m == @api.method}
                  >
                    {m}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium">Visibility</label>
                <select
                  name="visibility"
                  class="mt-1 w-full rounded-md border bg-background px-3 py-1.5 text-sm"
                >
                  <option value="private" selected={@api.visibility == "private"}>Private</option>
                  <option value="public" selected={@api.visibility == "public"}>Public</option>
                </select>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <input
                type="checkbox"
                id="requires_auth"
                name="requires_auth"
                value="true"
                checked={@api.requires_auth}
                class="rounded border"
              />
              <label for="requires_auth" class="text-xs font-medium">
                Require authentication (API key)
              </label>
            </div>
            <button
              type="submit"
              class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
            >
              Save Settings
            </button>
          </form>
        </div>
      </div>
    </.editor_shell>
    """
  end

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  def handle_event("publish", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Apis.publish(api, org) do
      {:ok, published_api} ->
        {:noreply,
         socket
         |> assign(api: published_api)
         |> load_metrics(published_api)
         |> put_flash(:info, "API published successfully")}

      {:error, :not_compiled} ->
        {:noreply, put_flash(socket, :error, "API must be compiled before publishing")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to publish API")}
    end
  end

  def handle_event("unpublish", _params, socket) do
    case Apis.unpublish(socket.assigns.api) do
      {:ok, updated_api} ->
        {:noreply,
         socket
         |> assign(api: updated_api)
         |> put_flash(:info, "API unpublished")}

      {:error, :not_published} ->
        {:noreply, put_flash(socket, :error, "API is not published")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish API")}
    end
  end

  def handle_event("save_publish_settings", params, socket) do
    attrs = %{
      method: params["method"],
      visibility: params["visibility"],
      requires_auth: params["requires_auth"] == "true"
    }

    case Apis.update_api(socket.assigns.api, attrs) do
      {:ok, api} ->
        {:noreply,
         socket
         |> assign(api: api, test_url: "/api/#{socket.assigns.org.slug}/#{api.slug}")
         |> put_flash(:info, "Settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  def handle_event("copy_url", _params, socket) do
    url = "/api/#{socket.assigns.org.slug}/#{socket.assigns.api.slug}"
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  # ── Private ───────────────────────────────────────────────────────────

  @spec init_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp init_assigns(socket) do
    socket
    |> assign(metrics: nil)
    |> load_metrics(socket.assigns.api)
  end

  @spec load_metrics(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp load_metrics(socket, api) do
    api_id = api.id

    metrics = %{
      count_24h: Analytics.invocations_count(api_id, period: :day),
      success_rate: Analytics.success_rate(api_id, period: :day),
      avg_latency: Analytics.avg_latency(api_id, period: :day),
      error_count: Analytics.error_count(api_id, period: :day)
    }

    assign(socket, metrics: metrics)
  end

  @spec shared_shell_assigns(map()) :: map()
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
