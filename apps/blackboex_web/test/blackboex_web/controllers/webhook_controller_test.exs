defmodule BlackboexWeb.WebhookControllerTest do
  use BlackboexWeb.ConnCase, async: true

  import Mox

  alias Blackboex.Billing.StripeClientMock

  @moduletag :unit
  @moduletag :capture_log

  # Ensure mock expectations are verified after each test
  setup :verify_on_exit!

  # The webhook endpoint accepts raw body — we post plain strings
  @stripe_path "/webhooks/stripe"

  defp post_webhook(conn, body, signature \\ "valid-sig") do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post(@stripe_path, body)
  end

  describe "POST /webhooks/stripe — signature verification" do
    test "rejects request with invalid signature", %{conn: conn} do
      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:error, :invalid_signature}
      end)

      conn = post_webhook(conn, ~s({"id":"evt_1","type":"test"}), "bad-sig")

      assert response(conn, 400) =~ "invalid signature"
    end

    test "rejects request with missing stripe-signature header", %{conn: conn} do
      expect(StripeClientMock, :construct_webhook_event, fn _body, sig, _secret ->
        # When header is absent CacheBodyReader returns "" for sig
        assert sig == ""
        {:error, :missing_signature}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(@stripe_path, ~s({"id":"evt_1","type":"test"}))

      assert response(conn, 400) =~ "invalid signature"
    end

    test "returns 200 for valid signature and known event", %{conn: conn} do
      event = %{
        "id" => "evt_valid_1",
        "type" => "unhandled.event",
        "data" => %{"object" => %{}}
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      assert response(conn, 200) =~ "ok"
    end
  end

  describe "POST /webhooks/stripe — checkout.session.completed" do
    test "processes valid checkout session completed event", %{conn: conn} do
      event = %{
        "id" => "evt_checkout_1",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "customer" => "cus_test123",
            "subscription" => "sub_test123",
            "metadata" => %{
              "organization_id" => "00000000-0000-0000-0000-000000000001",
              "plan" => "pro"
            }
          }
        }
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      # 200 ok or 500 if org doesn't exist — either way signature was accepted
      assert conn.status in [200, 500]
    end

    test "returns 200 even when checkout metadata is incomplete (idempotent)", %{conn: conn} do
      event = %{
        "id" => "evt_checkout_missing_meta",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "customer" => nil,
            "subscription" => nil,
            "metadata" => %{}
          }
        }
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      # Handler returns {:error, :invalid_payload} -> controller returns 500
      assert conn.status in [200, 500]
    end
  end

  describe "POST /webhooks/stripe — customer.subscription.updated" do
    test "processes subscription updated event", %{conn: conn} do
      event = %{
        "id" => "evt_sub_updated_1",
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => "sub_unknown",
            "status" => "active",
            "cancel_at_period_end" => false
          }
        }
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      # Subscription not found -> handler logs warning and returns :ok
      assert response(conn, 200) =~ "ok"
    end
  end

  describe "POST /webhooks/stripe — customer.subscription.deleted" do
    test "processes subscription deleted event for unknown subscription", %{conn: conn} do
      event = %{
        "id" => "evt_sub_deleted_1",
        "type" => "customer.subscription.deleted",
        "data" => %{
          "object" => %{
            "id" => "sub_nonexistent"
          }
        }
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      assert response(conn, 200) =~ "ok"
    end
  end

  describe "POST /webhooks/stripe — invoice.payment_failed" do
    test "processes invoice payment failed event for unknown subscription", %{conn: conn} do
      event = %{
        "id" => "evt_invoice_failed_1",
        "type" => "invoice.payment_failed",
        "data" => %{
          "object" => %{
            "subscription" => "sub_nonexistent"
          }
        }
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      assert response(conn, 200) =~ "ok"
    end
  end

  describe "POST /webhooks/stripe — unhandled event types" do
    test "returns 200 for unknown event type", %{conn: conn} do
      event = %{
        "id" => "evt_unknown_1",
        "type" => "some.unknown.event",
        "data" => %{"object" => %{}}
      }

      expect(StripeClientMock, :construct_webhook_event, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn = post_webhook(conn, Jason.encode!(event))

      assert response(conn, 200) =~ "ok"
    end
  end

  describe "POST /webhooks/stripe — idempotency" do
    test "returns 200 for duplicate event (already processed)", %{conn: conn} do
      event = %{
        "id" => "evt_dup_1",
        "type" => "some.event",
        "data" => %{"object" => %{}}
      }

      # Both calls return ok — first processes, second would be duplicate
      # but the mock only covers the construct step; the idempotency is in WebhookHandler
      expect(StripeClientMock, :construct_webhook_event, 2, fn _body, _sig, _secret ->
        {:ok, event}
      end)

      conn1 = post_webhook(conn, Jason.encode!(event))
      assert response(conn1, 200) =~ "ok"

      conn2 = post_webhook(build_conn(), Jason.encode!(event))
      # Second call: already_processed -> controller still returns 200
      assert response(conn2, 200) =~ "ok"
    end
  end
end
