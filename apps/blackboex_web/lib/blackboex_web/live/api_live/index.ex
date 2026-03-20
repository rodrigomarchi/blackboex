defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization with 24h stats.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Apis.DashboardQueries

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    {api_rows, org_slug} =
      if org do
        {DashboardQueries.list_apis_with_stats(org.id), org.slug}
      else
        {[], nil}
      end

    {:ok, assign(socket, api_rows: api_rows, org_slug: org_slug, search: "", page_title: "APIs")}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    query = String.slice(query, 0, 200)
    org = socket.assigns.current_scope.organization

    api_rows =
      if org do
        DashboardQueries.list_apis_with_stats(org.id, search: query)
      else
        []
      end

    {:noreply, assign(socket, api_rows: api_rows, search: query)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    org = socket.assigns.current_scope.organization

    case org && Blackboex.Apis.get_api(org.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "API not found.")}

      %{status: "draft"} = api ->
        case Blackboex.Apis.update_api(api, %{status: "archived"}) do
          {:ok, _api} ->
            api_rows =
              DashboardQueries.list_apis_with_stats(org.id, search: socket.assigns.search)

            {:noreply, socket |> assign(api_rows: api_rows) |> put_flash(:info, "API archived.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not delete API.")}
        end

      _non_draft ->
        {:noreply, put_flash(socket, :error, "Only draft APIs can be deleted.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">APIs</h1>
          <p class="text-muted-foreground">Manage and monitor your API endpoints</p>
        </div>
        <.link
          navigate={~p"/apis/new"}
          class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Create API
        </.link>
      </div>

      <form phx-change="search" class="w-full">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder="Search APIs by name or description..."
          phx-debounce="300"
          class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
      </form>

      <%= if @api_rows == [] do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <div class="flex flex-col items-center justify-center space-y-4 py-8">
            <div class="text-center space-y-2">
              <h3 class="text-lg font-semibold">No APIs found</h3>
              <p class="text-sm text-muted-foreground">
                <%= if @search != "" do %>
                  No APIs match your search. Try a different query.
                <% else %>
                  Get started by creating your first API endpoint.
                <% end %>
              </p>
            </div>
            <.link
              :if={@search == ""}
              navigate={~p"/apis/new"}
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
            >
              Create API
            </.link>
          </div>
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={row <- @api_rows}
            class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1 space-y-1">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/apis/#{row.api.id}"}
                    class="font-semibold hover:underline truncate"
                  >
                    {row.api.name}
                  </.link>
                  <.status_badge status={row.api.status} />
                </div>

                <p :if={row.api.description} class="text-sm text-muted-foreground truncate">
                  {row.api.description}
                </p>

                <div class="flex items-center gap-3 text-xs text-muted-foreground">
                  <span>{row.calls_24h} calls</span>
                  <span>&middot;</span>
                  <span>{format_latency(row.avg_latency)} avg</span>
                  <span>&middot;</span>
                  <span>{row.errors_24h} errors</span>
                  <span>&middot;</span>
                  <span>{Calendar.strftime(row.api.inserted_at, "%Y-%m-%d")}</span>
                </div>

                <%= if row.api.status == "published" do %>
                  <div class="flex items-center gap-2 pt-1">
                    <code class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                      POST /api/{@org_slug}/{row.api.slug}
                    </code>
                  </div>
                <% else %>
                  <p class="text-xs italic text-muted-foreground pt-1">Not published</p>
                <% end %>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <.link
                  navigate={~p"/apis/#{row.api.id}/edit"}
                  class="inline-flex items-center rounded-md border px-2.5 py-1 text-xs font-medium hover:bg-accent"
                >
                  Edit
                </.link>
                <.link
                  :if={row.api.status == "draft"}
                  phx-click="delete"
                  phx-value-id={row.api.id}
                  data-confirm="Are you sure you want to delete this API?"
                  class="inline-flex items-center rounded-md border border-destructive/50 px-2.5 py-1 text-xs font-medium text-destructive hover:bg-destructive/10"
                >
                  Delete
                </.link>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge(assigns) do
    color_classes =
      case assigns.status do
        "published" ->
          "border-green-500/30 bg-green-500/10 text-green-700 dark:text-green-400"

        "compiled" ->
          "border-border bg-secondary text-secondary-foreground"

        _draft_or_other ->
          "border-border bg-muted text-muted-foreground"
      end

    assigns = assign(assigns, :color_classes, color_classes)

    ~H"""
    <span class={"inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-semibold #{@color_classes}"}>
      {@status}
    </span>
    """
  end

  defp format_latency(nil), do: "--"
  defp format_latency(ms) when ms < 1, do: "<1ms"
  defp format_latency(ms), do: "#{round(ms)}ms"
end
