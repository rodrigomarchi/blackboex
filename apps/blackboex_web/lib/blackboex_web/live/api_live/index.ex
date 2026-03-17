defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Apis

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    apis = if org, do: Apis.list_apis(org.id), else: []
    {:ok, assign(socket, apis: apis, page_title: "APIs")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">APIs</h1>
            <p class="text-muted-foreground">Manage your API endpoints</p>
          </div>
          <.link
            navigate={~p"/apis/new"}
            class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
          >
            <.icon name="hero-plus" class="mr-2 size-4" /> Create API
          </.link>
        </div>

        <%= if @apis == [] do %>
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
            <div class="flex flex-col items-center justify-center space-y-4 py-8">
              <div class="text-center space-y-2">
                <h3 class="text-lg font-semibold">No APIs created yet</h3>
                <p class="text-sm text-muted-foreground">
                  Get started by creating your first API endpoint.
                </p>
              </div>
              <.link
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
              :for={api <- @apis}
              class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm"
            >
              <div class="flex items-center justify-between">
                <.link navigate={~p"/apis/#{api.id}"} class="block">
                  <h3 class="font-semibold hover:underline">{api.name}</h3>
                  <p class="text-sm text-muted-foreground">{api.description}</p>
                </.link>
                <div class="flex items-center gap-3">
                  <span class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold">
                    {api.status}
                  </span>
                  <span class="text-xs text-muted-foreground">
                    {Calendar.strftime(api.inserted_at, "%Y-%m-%d")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
