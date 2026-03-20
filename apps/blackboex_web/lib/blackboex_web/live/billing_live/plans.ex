defmodule BlackboexWeb.BillingLive.Plans do
  @moduledoc """
  LiveView for displaying billing plans and initiating checkout.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Billing

  @plans [
    %{
      id: "free",
      name: "Free",
      price: "$0",
      period: "/month",
      features: [
        "10 APIs",
        "1,000 invocations/day",
        "50 LLM generations/month",
        "Community support"
      ]
    },
    %{
      id: "pro",
      name: "Pro",
      price: "$29",
      period: "/month",
      features: [
        "50 APIs",
        "50,000 invocations/day",
        "500 LLM generations/month",
        "Priority support",
        "Custom domains"
      ]
    },
    %{
      id: "enterprise",
      name: "Enterprise",
      price: "$99",
      period: "/month",
      features: [
        "Unlimited APIs",
        "Unlimited invocations",
        "Unlimited LLM generations",
        "Dedicated support",
        "Custom domains",
        "Collaborative editing"
      ]
    }
  ]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    subscription = Billing.get_subscription(org.id)
    current_plan = if subscription, do: subscription.plan, else: "free"

    {:ok, assign(socket, plans: @plans, current_plan: current_plan, loading_plan: nil)}
  end

  @impl true
  def handle_event("choose_plan", %{"plan" => plan}, socket) when plan in ~w(pro enterprise) do
    if socket.assigns.loading_plan do
      {:noreply, socket}
    else
      socket = assign(socket, loading_plan: plan)
      org = socket.assigns.current_scope.organization

      success_url = url(socket, ~p"/billing/manage") <> "?checkout=success"
      cancel_url = url(socket, ~p"/billing")

      case Billing.create_checkout_session(org, plan, success_url, cancel_url) do
        {:ok, %{url: url}} ->
          {:noreply, redirect(socket, external: url)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(loading_plan: nil)
           |> put_flash(:error, "Could not create checkout session. Please try again.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8">
      <div class="text-center mb-10">
        <h1 class="text-3xl font-bold">Choose your plan</h1>
        <p class="text-base-content/60 mt-2">Scale your API platform with the right plan</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div
          :for={plan <- @plans}
          class={[
            "card bg-base-100 border shadow-sm",
            plan.id == @current_plan && "border-primary ring-2 ring-primary"
          ]}
        >
          <div class="card-body">
            <h2 class="card-title">{plan.name}</h2>
            <div class="mt-2">
              <span class="text-3xl font-bold">{plan.price}</span>
              <span class="text-base-content/60">{plan.period}</span>
            </div>

            <ul class="mt-6 space-y-2">
              <li :for={feature <- plan.features} class="flex items-center gap-2">
                <.icon name="hero-check" class="size-4 text-success" />
                <span class="text-sm">{feature}</span>
              </li>
            </ul>

            <div class="card-actions mt-6">
              <%= if plan.id == @current_plan do %>
                <button class="btn btn-outline btn-block" disabled>Current Plan</button>
              <% else %>
                <%= if plan.id == "free" do %>
                  <button class="btn btn-outline btn-block" disabled>Free</button>
                <% else %>
                  <button
                    class="btn btn-primary btn-block"
                    phx-click="choose_plan"
                    phx-value-plan={plan.id}
                    disabled={@loading_plan != nil}
                  >
                    <%= if @loading_plan == plan.id do %>
                      <span class="loading loading-spinner loading-sm"></span>
                    <% else %>
                      Choose {plan.name}
                    <% end %>
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
