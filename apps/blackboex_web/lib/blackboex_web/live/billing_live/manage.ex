defmodule BlackboexWeb.BillingLive.Manage do
  @moduledoc """
  LiveView for managing an existing billing subscription.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Spinner
  import BlackboexWeb.Components.Shared.EmptyState
  import BlackboexWeb.Components.Shared.DescriptionList

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
      <.header>
        Subscription Management
      </.header>

      <%= if @subscription do %>
        <.card>
          <.card_content class="pt-6">
            <.description_list>
              <:item label="Plan">
                <span class="font-semibold capitalize">{@subscription.plan}</span>
              </:item>
              <:item label="Status">
                <.badge class={subscription_classes(@subscription.status)}>
                  {@subscription.status}
                </.badge>
              </:item>
              <:item label="Current Period">
                <%= if @subscription.current_period_start && @subscription.current_period_end do %>
                  {Calendar.strftime(@subscription.current_period_start, "%b %d, %Y")} — {Calendar.strftime(
                    @subscription.current_period_end,
                    "%b %d, %Y"
                  )}
                <% else %>
                  —
                <% end %>
              </:item>
              <:item label="Auto-Renew">
                {if @subscription.cancel_at_period_end,
                  do: "Cancels at end of period",
                  else: "Active"}
              </:item>
            </.description_list>

            <div class="flex gap-2 pt-2 mt-6">
              <.button variant="primary" phx-click="manage" disabled={@loading_portal}>
                <%= if @loading_portal do %>
                  <.spinner />
                <% end %>
                Manage Subscription
              </.button>
              <.button navigate={~p"/billing"} variant="default">
                Change Plan
              </.button>
            </div>
          </.card_content>
        </.card>
      <% else %>
        <.empty_state
          title="No active subscription"
          description="You don't have an active subscription."
        >
          <:actions>
            <.button navigate={~p"/billing"} variant="primary">
              View Plans
            </.button>
          </:actions>
        </.empty_state>
      <% end %>
    </div>
    """
  end
end
