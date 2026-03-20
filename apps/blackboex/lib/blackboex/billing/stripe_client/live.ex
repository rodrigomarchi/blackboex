defmodule Blackboex.Billing.StripeClient.Live do
  @moduledoc """
  Real Stripe client implementation using stripity_stripe.
  """

  @behaviour Blackboex.Billing.StripeClient

  @impl true
  @spec create_checkout_session(Blackboex.Billing.StripeClient.checkout_params()) ::
          {:ok, Blackboex.Billing.StripeClient.checkout_result()} | {:error, term()}
  def create_checkout_session(params) do
    stripe_params = %{
      mode: "subscription",
      customer_email: params.customer_email,
      line_items: [%{price: params.price_id, quantity: 1}],
      success_url: params.success_url,
      cancel_url: params.cancel_url,
      metadata: params.metadata
    }

    case Stripe.Checkout.Session.create(stripe_params) do
      {:ok, session} -> {:ok, %{id: session.id, url: session.url}}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  @spec create_portal_session(String.t(), String.t()) ::
          {:ok, Blackboex.Billing.StripeClient.portal_result()} | {:error, term()}
  def create_portal_session(customer_id, return_url) do
    params = %{customer: customer_id, return_url: return_url}

    case Stripe.BillingPortal.Session.create(params) do
      {:ok, session} -> {:ok, %{url: session.url}}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  @spec retrieve_subscription(String.t()) ::
          {:ok, Blackboex.Billing.StripeClient.subscription_result()} | {:error, term()}
  def retrieve_subscription(subscription_id) do
    case Stripe.Subscription.retrieve(subscription_id) do
      {:ok, sub} -> {:ok, sub}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  @spec construct_webhook_event(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def construct_webhook_event(payload, signature, secret) do
    Stripe.Webhook.construct_event(payload, signature, secret)
  end
end
