defmodule BlackboexWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView. Shows welcome message and quick actions.
  """
  use BlackboexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-muted-foreground">Welcome to BlackBoex</p>
        </div>

        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <div class="flex flex-col items-center justify-center space-y-4 py-8">
            <div class="text-center space-y-2">
              <h3 class="text-lg font-semibold">No APIs created yet</h3>
              <p class="text-sm text-muted-foreground">
                Get started by creating your first API endpoint.
              </p>
            </div>
            <button class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90">
              Create API
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
