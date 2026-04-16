defmodule BlackboexWeb.BillingLive.Plans do
  @moduledoc """
  LiveView for displaying billing plans and initiating checkout.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Spinner
  import BlackboexWeb.Components.Shared.ProgressBar
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.OrgSettingsLive, only: [org_settings_tabs: 1]

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

      success_url =
        BlackboexWeb.Endpoint.url() <>
          ~p"/billing/manage" <>
          "?checkout=success"

      cancel_url =
        BlackboexWeb.Endpoint.url() <> ~p"/billing"

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
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-sparkles" class="size-5 text-accent-amber" /> Choose your plan
        </span>
        <:subtitle>Scale your API platform with the right plan</:subtitle>
      </.header>

      <.org_settings_tabs current_scope={@current_scope} active="billing" />

      <.page_section :if={@usage}>
        <.card>
          <.card_content standalone>
            <div class="flex items-center justify-between mb-4">
              <.section_heading level="h1" compact>
                Current Plan: {@usage.plan}
              </.section_heading>
              <.button
                navigate={~p"/billing/manage"}
                variant="default"
                size="sm"
              >
                <.icon name="hero-cog-6-tooth" class="mr-1.5 size-3.5 text-slate-400" />
                Manage Subscription
              </.button>
            </div>

            <.section_heading level="h2" tone="muted" class="mb-3">
              Usage this month
            </.section_heading>
            <div class="space-y-4">
              <.progress_bar
                label="APIs"
                used={@usage.apis.used}
                limit={if @usage.apis.limit == :unlimited, do: "Unlimited", else: @usage.apis.limit}
                percentage={if @usage.apis.limit == :unlimited, do: 0.0, else: @usage.apis.pct * 1.0}
              />
              <.progress_bar
                label="Calls/day"
                used={@usage.invocations_today.used}
                limit={
                  if @usage.invocations_today.limit == :unlimited,
                    do: "Unlimited",
                    else: @usage.invocations_today.limit
                }
                percentage={
                  if @usage.invocations_today.limit == :unlimited,
                    do: 0.0,
                    else: @usage.invocations_today.pct * 1.0
                }
              />
              <.progress_bar
                label="LLM generations"
                used={@usage.llm_generations_month.used}
                limit={
                  if @usage.llm_generations_month.limit == :unlimited,
                    do: "Unlimited",
                    else: @usage.llm_generations_month.limit
                }
                percentage={
                  if @usage.llm_generations_month.limit == :unlimited,
                    do: 0.0,
                    else: @usage.llm_generations_month.pct * 1.0
                }
              />
            </div>
          </.card_content>
        </.card>
      </.page_section>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <.card
          :for={plan <- @plans}
          class={plan.id == @current_plan && "border-primary ring-2 ring-primary"}
        >
          <.card_content standalone>
            <.section_heading level="h1" compact>
              {plan.name}
            </.section_heading>
            <div class="mt-2">
              <span class="text-3xl font-bold">{plan.price}</span>
              <span class="text-muted-foreground">{plan.period}</span>
            </div>

            <ul class="mt-6 space-y-2">
              <li :for={feature <- plan.features} class="flex items-center gap-2">
                <.icon name="hero-check" class="size-4 text-accent-emerald" />
                <span class="text-sm">{feature}</span>
              </li>
            </ul>

            <.form_actions>
              <%= if plan.id == @current_plan do %>
                <.button variant="default" disabled class="w-full">
                  <.icon name="hero-check-circle" class="mr-1.5 size-3.5 text-slate-400" />
                  Current Plan
                </.button>
              <% else %>
                <%= if plan.id == "free" do %>
                  <.button variant="default" disabled class="w-full">
                    <.icon name="hero-check-circle" class="mr-1.5 size-3.5 text-slate-400" /> Free
                  </.button>
                <% else %>
                  <.button
                    variant="primary"
                    class="w-full"
                    phx-click="choose_plan"
                    phx-value-plan={plan.id}
                    disabled={@loading_plan != nil}
                  >
                    <%= if @loading_plan == plan.id do %>
                      <.spinner class="size-4 mr-2" />
                    <% else %>
                      <.icon name="hero-arrow-right" class="mr-1.5 size-3.5 text-accent-emerald" />
                      Choose {plan.name}
                    <% end %>
                  </.button>
                <% end %>
              <% end %>
            </.form_actions>
          </.card_content>
        </.card>
      </div>
    </.page>
    """
  end
end
