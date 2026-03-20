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
        <div class="card bg-base-100 border shadow-sm">
          <div class="card-body">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <span class="text-sm text-base-content/60">Plan</span>
                <p class="font-semibold capitalize">{@subscription.plan}</p>
              </div>
              <div>
                <span class="text-sm text-base-content/60">Status</span>
                <p>
                  <span class={[
                    "badge",
                    status_badge_class(@subscription.status)
                  ]}>
                    {@subscription.status}
                  </span>
                </p>
              </div>
              <div>
                <span class="text-sm text-base-content/60">Current Period</span>
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
                <span class="text-sm text-base-content/60">Auto-Renew</span>
                <p>
                  {if @subscription.cancel_at_period_end,
                    do: "Cancels at end of period",
                    else: "Active"}
                </p>
              </div>
            </div>

            <div class="card-actions mt-6">
              <button
                class="btn btn-primary"
                phx-click="manage"
                disabled={@loading_portal}
              >
                <%= if @loading_portal do %>
                  <span class="loading loading-spinner loading-sm"></span>
                <% else %>
                  Manage Subscription
                <% end %>
              </button>
              <.link navigate={~p"/billing"} class="btn btn-outline">
                Change Plan
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-100 border shadow-sm">
          <div class="card-body text-center">
            <p class="text-base-content/60">You don't have an active subscription.</p>
            <div class="card-actions justify-center mt-4">
              <.link navigate={~p"/billing"} class="btn btn-primary">
                View Plans
              </.link>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("trialing"), do: "badge-info"
  defp status_badge_class("past_due"), do: "badge-warning"
  defp status_badge_class("canceled"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"
end
