defmodule BlackboexWeb.ApiLive.Edit.PublishLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [time_ago: 1]

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.Keys
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, init_assigns(socket)}
      {:error, socket} -> {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="publish">
      <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-6">
        <%!-- Status Header --%>
        <div class="rounded-lg border p-4 space-y-3">
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
                phx-click="request_confirm"
                phx-value-action="unpublish"
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

          <%= if @api.status == "published" && @published_version do %>
            <div class="flex items-center gap-2 text-xs">
              <span class="inline-flex items-center gap-1 rounded-full bg-success/10 px-2 py-0.5 text-success-foreground font-semibold">
                <.icon name="hero-signal" class="size-3" /> LIVE
              </span>
              <span>v{@published_version.version_number}</span>
              <span :if={@published_version.version_label} class="text-muted-foreground">
                ({@published_version.version_label})
              </span>
              <span class="text-muted-foreground">
                published {time_ago(@published_version.inserted_at)}
              </span>
            </div>
          <% end %>
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

        <%!-- Version Timeline --%>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Versions</h3>
          <%= if @versions == [] do %>
            <p class="text-sm text-muted-foreground">
              No versions yet. Save to create the first version.
            </p>
          <% else %>
            <div class="space-y-2">
              <%= for version <- @versions do %>
                <div class={[
                  "rounded border p-3 text-xs space-y-1",
                  if(published_version?(version, @published_version),
                    do: "border-success bg-success/5",
                    else: ""
                  )
                ]}>
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="font-semibold">v{version.version_number}</span>
                      <%= if published_version?(version, @published_version) do %>
                        <span class="inline-flex items-center gap-1 rounded-full bg-success/10 px-1.5 py-0.5 text-[10px] font-semibold text-success-foreground">
                          LIVE
                        </span>
                      <% end %>
                      <span class={[
                        "inline-flex items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                        compilation_status_classes(version.compilation_status)
                      ]}>
                        {compilation_status_label(version.compilation_status)}
                      </span>
                    </div>
                    <span class="text-muted-foreground">
                      {Calendar.strftime(version.inserted_at, "%H:%M")}
                    </span>
                  </div>

                  <div class="text-muted-foreground">
                    {humanize_source(version.source)}
                    <%= if version.diff_summary do %>
                      — {version.diff_summary}
                    <% end %>
                  </div>

                  <div class="flex gap-2">
                    <button
                      phx-click="view_version"
                      phx-value-number={version.version_number}
                      class="text-primary hover:underline"
                    >
                      View
                    </button>
                    <%= if can_publish_version?(version, @published_version, @api.status) do %>
                      <button
                        phx-click="request_confirm"
                        phx-value-action="publish_version"
                        phx-value-number={version.version_number}
                        class="text-info hover:underline font-medium"
                      >
                        Publish this version
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

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

        <%!-- Authentication & Keys Summary --%>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Authentication</h3>
          <div class="rounded-lg border p-4 space-y-3">
            <form phx-submit="save_publish_settings">
              <div class="flex items-center justify-between">
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
                    Require API key
                  </label>
                </div>
                <button
                  type="submit"
                  class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
                >
                  Save
                </button>
              </div>
            </form>

            <div class="border-t pt-3 space-y-2">
              <div class="flex items-center justify-between text-xs">
                <span class="text-muted-foreground">
                  {@keys_summary.active_count} active
                  <%= if @keys_summary.revoked_count > 0 do %>
                    , {@keys_summary.revoked_count} revoked
                  <% end %>
                </span>
                <a
                  href="/api-keys"
                  class="text-primary hover:underline text-xs font-medium"
                >
                  Manage Keys
                </a>
              </div>
              <%= if @keys_summary.active_keys != [] do %>
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={key <- @keys_summary.active_keys}
                    class="inline-flex items-center rounded bg-muted px-2 py-0.5 font-mono text-[10px]"
                  >
                    {key.key_prefix}...
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

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
            </div>
          </div>
        <% end %>
      </div>

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />
    </.editor_shell>
    """
  end

  # ── Events: command palette ──────────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── Confirm Dialog ────────────────────────────────────────────────────

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
      nil -> {:noreply, socket}
      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
    end
  end

  # ── Events: publish actions ──────────────────────────────────────────

  def handle_event("publish", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Apis.publish(api, org) do
      {:ok, published_api} ->
        {:noreply,
         socket
         |> assign(api: published_api)
         |> assign(published_version: Apis.published_version(published_api.id))
         |> assign(versions: Apis.list_versions(published_api.id))
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
         |> assign(api: updated_api, published_version: nil, metrics: nil)
         |> put_flash(:info, "API unpublished")}

      {:error, :not_published} ->
        {:noreply, put_flash(socket, :error, "API is not published")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish API")}
    end
  end

  def handle_event("publish_version", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    %{api: api, org: org} = socket.assigns

    latest = hd(socket.assigns.versions)

    result =
      if number == latest.version_number do
        ensure_compiled_and_publish(api, org)
      else
        with {:ok, _rollback_v} <-
               Apis.rollback_to_version(api, number, socket.assigns.current_scope.user.id) do
          reloaded_api = Apis.get_api(org.id, api.id)
          ensure_compiled_and_publish(reloaded_api, org)
        end
      end

    case result do
      {:ok, published_api} ->
        {:noreply,
         socket
         |> assign(api: published_api)
         |> assign(published_version: Apis.published_version(published_api.id))
         |> assign(versions: Apis.list_versions(published_api.id))
         |> load_metrics(published_api)
         |> put_flash(:info, "Published v#{number}")}

      {:error, :not_compiled} ->
        {:noreply, put_flash(socket, :error, "Version must be compiled before publishing")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to publish version")}
    end
  end

  def handle_event("view_version", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    version = Apis.get_version(socket.assigns.api.id, number)

    if version do
      {:noreply, assign(socket, selected_version: version)}
    else
      {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  def handle_event("clear_version_view", _params, socket) do
    {:noreply, assign(socket, selected_version: nil)}
  end

  def handle_event("save_publish_settings", params, socket) do
    attrs = %{requires_auth: params["requires_auth"] == "true"}

    case Apis.update_api(socket.assigns.api, attrs) do
      {:ok, api} ->
        {:noreply,
         socket
         |> assign(api: api)
         |> put_flash(:info, "Settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  def handle_event("copy_url", _params, socket) do
    url = "/api/#{socket.assigns.org.slug}/#{socket.assigns.api.slug}"
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp build_confirm("unpublish", _params) do
    %{
      title: "Unpublish API?",
      description: "The API will no longer be accessible to consumers. You can republish it later.",
      variant: :warning,
      confirm_label: "Unpublish",
      event: "unpublish",
      meta: %{}
    }
  end

  defp build_confirm("publish_version", params) do
    %{
      title: "Publish this version?",
      description: "This will make it the live version. The current published version will be replaced.",
      variant: :info,
      confirm_label: "Publish",
      event: "publish_version",
      meta: Map.take(params, ["number"])
    }
  end

  defp build_confirm(_, _), do: nil

  @spec init_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp init_assigns(socket) do
    api = socket.assigns.api

    socket
    |> assign(
      metrics: nil,
      published_version: Apis.published_version(api.id),
      keys_summary: Keys.keys_summary(api.id),
      confirm: nil
    )
    |> load_metrics(api)
  end

  @spec load_metrics(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp load_metrics(socket, %{status: "published"} = api) do
    api_id = api.id

    metrics = %{
      count_24h: Analytics.invocations_count(api_id, period: :day),
      success_rate: Analytics.success_rate(api_id, period: :day),
      avg_latency: Analytics.avg_latency(api_id, period: :day),
      error_count: Analytics.error_count(api_id, period: :day)
    }

    assign(socket, metrics: metrics)
  end

  defp load_metrics(socket, _api), do: socket

  @spec ensure_compiled_and_publish(Apis.Api.t(), map()) ::
          {:ok, Apis.Api.t()} | {:error, term()}
  defp ensure_compiled_and_publish(%{status: "compiled"} = api, org), do: Apis.publish(api, org)
  defp ensure_compiled_and_publish(_, _), do: {:error, :not_compiled}

  @spec published_version?(map(), map() | nil) :: boolean()
  defp published_version?(_version, nil), do: false

  defp published_version?(version, published),
    do: version.version_number == published.version_number

  @spec can_publish_version?(map(), map() | nil, String.t()) :: boolean()
  defp can_publish_version?(version, published_version, api_status) do
    version.compilation_status == "success" and
      api_status in ["compiled", "published"] and
      not published_version?(version, published_version)
  end

  @spec compilation_status_classes(String.t()) :: String.t()
  defp compilation_status_classes("success"), do: "bg-success/10 text-success-foreground"
  defp compilation_status_classes("error"), do: "bg-destructive/10 text-destructive"
  defp compilation_status_classes(_), do: "bg-muted text-muted-foreground"

  @spec compilation_status_label(String.t()) :: String.t()
  defp compilation_status_label("success"), do: "Compiled"
  defp compilation_status_label("error"), do: "Failed"
  defp compilation_status_label(_), do: "Pending"

  @spec humanize_source(String.t()) :: String.t()
  defp humanize_source("manual_edit"), do: "manual edit"
  defp humanize_source("chat_edit"), do: "chat edit"
  defp humanize_source(source), do: source

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
