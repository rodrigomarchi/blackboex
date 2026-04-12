defmodule BlackboexWeb.ApiLive.Edit.PublishLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.PublishLiveComponents
  import BlackboexWeb.ApiLive.Edit.PublishLiveHelpers

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.Keys
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette toggle_chat close_panels command_palette_search
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
      <.editor_tab_panel max_width="3xl" padding="sm">
        <.status_header api={@api} org={@org} published_version={@published_version} />

        <%= if @api.status == "draft" do %>
          <p class="text-muted-description">
            Save the API to compile it. Once compiled, you can publish.
          </p>
        <% end %>

        <%= if @api.status == "compiled" do %>
          <p class="text-muted-description">
            Ready to publish. A default API key will be created automatically.
          </p>
        <% end %>

        <.version_timeline
          versions={@versions}
          published_version={@published_version}
          api_status={@api.status}
        />

        <%= if @api.status == "published" && @metrics do %>
          <.metrics_grid metrics={@metrics} />
        <% end %>

        <.auth_section api={@api} keys_summary={@keys_summary} />

        <%= if @api.status in ["compiled", "published"] do %>
          <.docs_section org={@org} api={@api} />
        <% end %>
      </.editor_tab_panel>

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
      nil ->
        {:noreply, socket}

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
