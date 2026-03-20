defmodule BlackboexWeb.WebhookController do
  @moduledoc """
  Controller for processing Stripe webhook events.
  Verifies signature, ensures idempotent processing, and delegates to WebhookHandler.
  """

  use BlackboexWeb, :controller

  alias Blackboex.Billing.{StripeClient, WebhookHandler}
  alias BlackboexWeb.Plugs.CacheBodyReader

  require Logger

  @spec handle(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle(conn, _params) do
    raw_body = CacheBodyReader.get_raw_body(conn)
    signature = get_stripe_signature(conn)
    webhook_secret = Application.get_env(:blackboex, :stripe_webhook_secret, "")

    case StripeClient.client().construct_webhook_event(raw_body, signature, webhook_secret) do
      {:ok, event} ->
        process_verified_event(conn, event)

      {:error, reason} ->
        Logger.warning("Webhook signature verification failed: #{inspect(reason)}")
        send_resp(conn, 400, "invalid signature")
    end
  end

  defp process_verified_event(conn, event) do
    event_id = event["id"] || event[:id]
    event_type = event["type"] || event[:type]
    data_object = get_in(event, ["data", "object"]) || get_in(event, [:data, :object]) || %{}

    case WebhookHandler.process_event(event_id, event_type, data_object) do
      :ok ->
        send_resp(conn, 200, "ok")

      {:error, :already_processed} ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("Webhook processing failed: #{inspect(reason)}")
        send_resp(conn, 500, "processing failed")
    end
  end

  defp get_stripe_signature(conn) do
    case Plug.Conn.get_req_header(conn, "stripe-signature") do
      [sig | _] -> sig
      _ -> ""
    end
  end
end
