defmodule Blackboex.Billing.StripeClient do
  @moduledoc """
  Behaviour for Stripe API operations.
  Allows mocking in tests via Mox.
  """

  @type checkout_params :: %{
          customer_email: String.t(),
          price_id: String.t(),
          success_url: String.t(),
          cancel_url: String.t(),
          metadata: map()
        }

  @type checkout_result :: %{id: String.t(), url: String.t()}
  @type portal_result :: %{url: String.t()}
  @type subscription_result :: map()

  @callback create_checkout_session(checkout_params()) ::
              {:ok, checkout_result()} | {:error, term()}

  @callback create_portal_session(String.t(), String.t()) ::
              {:ok, portal_result()} | {:error, term()}

  @callback retrieve_subscription(String.t()) ::
              {:ok, subscription_result()} | {:error, term()}

  @callback construct_webhook_event(String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}

  @spec client() :: module()
  def client do
    Application.fetch_env!(:blackboex, :stripe_client)
  end
end
