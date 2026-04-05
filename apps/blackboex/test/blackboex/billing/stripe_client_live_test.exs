defmodule Blackboex.Billing.StripeClient.LiveTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Billing.StripeClient.Live

  # ──────────────────────────────────────────────────────────────
  # Behaviour compliance
  # ──────────────────────────────────────────────────────────────

  describe "behaviour compliance" do
    setup do
      Code.ensure_loaded!(Live)
      :ok
    end

    test "implements StripeClient behaviour" do
      behaviours =
        Live.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Blackboex.Billing.StripeClient in behaviours
    end

    test "exports create_checkout_session/1" do
      assert function_exported?(Live, :create_checkout_session, 1)
    end

    test "exports create_portal_session/2" do
      assert function_exported?(Live, :create_portal_session, 2)
    end

    test "exports retrieve_subscription/1" do
      assert function_exported?(Live, :retrieve_subscription, 1)
    end

    test "exports construct_webhook_event/3" do
      assert function_exported?(Live, :construct_webhook_event, 3)
    end
  end

  # NOTE: We don't test actual Stripe API calls here — that would require
  # a real Stripe API key and network access. The Mox mock
  # (StripeClientMock) is used for unit tests of modules that depend on
  # the Stripe client (WebhookHandler, Billing context, etc.).
end
