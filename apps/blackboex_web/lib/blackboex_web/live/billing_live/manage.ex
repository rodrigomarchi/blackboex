defmodule BlackboexWeb.BillingLive.Manage do
  @moduledoc """
  LiveView for managing an existing billing subscription.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Billing

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    subscription = Billing.get_subscription(org.id)

    {:ok, assign(socket, subscription: subscription, loading_portal: false)}
  end

  @impl true
  def handle_event("manage", _params, socket) do
    if socket.assigns.loading_portal do
      {:noreply, socket}
    else
      socket = assign(socket, loading_portal: true)
      org = socket.assigns.current_scope.organization
      return_url = url(socket, ~p"/billing/manage")

      case Billing.create_portal_session(org, return_url) do
        {:ok, %{url: url}} ->
          {:noreply, redirect(socket, external: url)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(loading_portal: false)
           |> put_flash(:error, "Could not open billing portal. Please try again.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8">
      <h1 class="text-2xl font-bold mb-6">Subscription Management</h1>

      <%= if @subscription do %>
        <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
          <div class="p-6">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <span class="text-sm text-muted-foreground">Plan</span>
                <p class="font-semibold capitalize">{@subscription.plan}</p>
              </div>
              <div>
                <span class="text-sm text-muted-foreground">Status</span>
                <p>
                  <span class={[
                    "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
                    status_badge_class(@subscription.status)
                  ]}>
                    {@subscription.status}
                  </span>
                </p>
              </div>
              <div>
                <span class="text-sm text-muted-foreground">Current Period</span>
                <p class="text-sm">
                  <%= if @subscription.current_period_start && @subscription.current_period_end do %>
                    {Calendar.strftime(@subscription.current_period_start, "%b %d, %Y")} — {Calendar.strftime(
                      @subscription.current_period_end,
                      "%b %d, %Y"
                    )}
                  <% else %>
                    —
                  <% end %>
                </p>
              </div>
              <div>
                <span class="text-sm text-muted-foreground">Auto-Renew</span>
                <p>
                  {if @subscription.cancel_at_period_end,
                    do: "Cancels at end of period",
                    else: "Active"}
                </p>
              </div>
            </div>

            <div class="flex gap-2 pt-2 mt-6">
              <button
                class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
                phx-click="manage"
                disabled={@loading_portal}
              >
                <%= if @loading_portal do %>
                  <svg class="animate-spin size-4 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                <% else %>
                  Manage Subscription
                <% end %>
              </button>
              <.link
                navigate={~p"/billing"}
                class="inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium hover:bg-accent hover:text-accent-foreground"
              >
                Change Plan
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
          <div class="p-6 text-center">
            <p class="text-muted-foreground">You don't have an active subscription.</p>
            <div class="flex justify-center mt-4">
              <.link
                navigate={~p"/billing"}
                class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
              >
                View Plans
              </.link>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge_class(status), do: subscription_classes(status)
end
