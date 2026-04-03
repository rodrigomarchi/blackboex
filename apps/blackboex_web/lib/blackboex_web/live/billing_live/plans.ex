defmodule BlackboexWeb.BillingLive.Plans do
  @moduledoc """
  LiveView for displaying billing plans and initiating checkout.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Billing
  alias Blackboex.Billing.Enforcement

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

    if org do
      subscription = Billing.get_subscription(org.id)
      current_plan = if subscription, do: subscription.plan, else: "free"
      usage = Enforcement.get_usage_details(org)

      {:ok,
       assign(socket,
         plans: @plans,
         current_plan: current_plan,
         loading_plan: nil,
         usage: usage
       )}
    else
      {:ok,
       assign(socket,
         plans: @plans,
         current_plan: "free",
         loading_plan: nil,
         usage: nil
       )}
    end
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
        <p class="text-muted-foreground mt-2">Scale your API platform with the right plan</p>
      </div>

      <div :if={@usage} class="rounded-lg border bg-card text-card-foreground shadow-sm mb-8">
        <div class="p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold">Current Plan: {@usage.plan}</h2>
            <.link
              navigate={~p"/billing/manage"}
              class="inline-flex items-center justify-center rounded-md border border-input bg-background px-3 py-1 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
            >
              Manage Subscription
            </.link>
          </div>

          <h3 class="text-sm font-semibold text-muted-foreground mb-3">Usage this month</h3>
          <div class="space-y-4">
            <.usage_bar label="APIs" detail={@usage.apis} />
            <.usage_bar label="Calls/day" detail={@usage.invocations_today} />
            <.usage_bar label="LLM generations" detail={@usage.llm_generations_month} />
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div
          :for={plan <- @plans}
          class={[
            "rounded-lg border bg-card text-card-foreground shadow-sm",
            plan.id == @current_plan && "border-primary ring-2 ring-primary"
          ]}
        >
          <div class="p-6">
            <h2 class="text-lg font-semibold">{plan.name}</h2>
            <div class="mt-2">
              <span class="text-3xl font-bold">{plan.price}</span>
              <span class="text-muted-foreground">{plan.period}</span>
            </div>

            <ul class="mt-6 space-y-2">
              <li :for={feature <- plan.features} class="flex items-center gap-2">
                <.icon name="hero-check" class="size-4 text-success" />
                <span class="text-sm">{feature}</span>
              </li>
            </ul>

            <div class="flex gap-2 pt-2 mt-6">
              <%= if plan.id == @current_plan do %>
                <button
                  class="inline-flex w-full items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium opacity-50 cursor-not-allowed"
                  disabled
                >
                  Current Plan
                </button>
              <% else %>
                <%= if plan.id == "free" do %>
                  <button
                    class="inline-flex w-full items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium opacity-50 cursor-not-allowed"
                    disabled
                  >
                    Free
                  </button>
                <% else %>
                  <button
                    class="inline-flex w-full items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
                    phx-click="choose_plan"
                    phx-value-plan={plan.id}
                    disabled={@loading_plan != nil}
                  >
                    <%= if @loading_plan == plan.id do %>
                      <svg class="animate-spin size-4 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
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

  @spec usage_bar(map()) :: Phoenix.LiveView.Rendered.t()
  defp usage_bar(%{detail: %{limit: :unlimited}} = assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex justify-between text-sm">
        <span>{@label}</span>
        <span>{@detail.used} / Unlimited</span>
      </div>
      <div class="h-2 rounded-full bg-muted">
        <div class="h-full rounded-full bg-success w-full"></div>
      </div>
    </div>
    """
  end

  defp usage_bar(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex justify-between text-sm">
        <span>{@label}</span>
        <span>{@detail.used} / {@detail.limit}</span>
      </div>
      <div class="h-2 rounded-full bg-muted">
        <div class="h-full rounded-full bg-primary" style={"width: #{min(@detail.pct, 100)}%"}></div>
      </div>
    </div>
    """
  end
end
