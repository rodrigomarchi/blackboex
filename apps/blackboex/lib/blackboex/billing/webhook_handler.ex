defmodule Blackboex.Billing.WebhookHandler do
  @moduledoc """
  Handles Stripe webhook events.
  Each event type has a dedicated handle_event/2 clause.
  """

  alias Blackboex.Billing
  alias Blackboex.Billing.ProcessedEvent
  alias Blackboex.Repo

  require Logger

  @spec process_event(String.t(), String.t(), map()) ::
          :ok | {:error, :already_processed} | {:error, term()}
  def process_event(event_id, event_type, payload) do
    Repo.transaction(fn ->
      with {:ok, _} <- mark_processed(event_id, event_type),
           :ok <- handle_event(event_type, payload) do
        :ok
      else
        {:error, %Ecto.Changeset{} = cs} ->
          handle_mark_error(event_id, cs)

        {:error, reason} ->
          Logger.warning("Webhook event #{event_id} failed: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, :already_processed} -> {:error, :already_processed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_mark_error(event_id, %Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :event_id) do
      Logger.info("Webhook event already processed: #{event_id}")
      Repo.rollback(:already_processed)
    else
      Logger.warning("Webhook event #{event_id} insert failed: #{inspect(errors)}")
      Repo.rollback(:insert_failed)
    end
  end

  @valid_plans ~w(free pro enterprise)

  @spec handle_event(String.t(), map()) :: :ok | {:error, term()}
  def handle_event("checkout.session.completed", payload) do
    metadata = payload["metadata"] || %{}
    org_id = metadata["organization_id"]
    plan = metadata["plan"]
    customer_id = payload["customer"]
    subscription_id = payload["subscription"]

    with :ok <- validate_non_empty_binary(org_id, "organization_id"),
         :ok <- validate_non_empty_binary(customer_id, "customer"),
         :ok <- validate_non_empty_binary(subscription_id, "subscription"),
         :ok <- validate_plan(plan) do
      ensure_subscription(org_id, customer_id, subscription_id, plan)
    else
      {:error, :invalid_payload} = err ->
        Logger.warning("checkout.session.completed invalid payload")
        err
    end
  end

  def handle_event("customer.subscription.updated", payload) do
    subscription_id = payload["id"]
    status = payload["status"]
    cancel_at_period_end = payload["cancel_at_period_end"] || false

    case Repo.get_by(Blackboex.Billing.Subscription, stripe_subscription_id: subscription_id) do
      nil ->
        Logger.warning("Subscription not found for stripe_subscription_id: #{subscription_id}")
        :ok

      sub ->
        attrs = %{
          organization_id: sub.organization_id,
          status: to_string(status),
          cancel_at_period_end: cancel_at_period_end
        }

        attrs =
          if is_integer(payload["current_period_start"]) &&
               is_integer(payload["current_period_end"]) do
            Map.merge(attrs, %{
              current_period_start: DateTime.from_unix!(payload["current_period_start"]),
              current_period_end: DateTime.from_unix!(payload["current_period_end"])
            })
          else
            attrs
          end

        case Billing.create_or_update_subscription(attrs) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def handle_event("customer.subscription.deleted", payload) do
    subscription_id = payload["id"]

    case Repo.get_by(Blackboex.Billing.Subscription, stripe_subscription_id: subscription_id) do
      nil ->
        :ok

      sub ->
        case Billing.create_or_update_subscription(%{
               organization_id: sub.organization_id,
               plan: "free",
               status: "canceled"
             }) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def handle_event("invoice.payment_failed", payload) do
    subscription_id = payload["subscription"]

    case Repo.get_by(Blackboex.Billing.Subscription, stripe_subscription_id: subscription_id) do
      nil ->
        :ok

      sub ->
        case Billing.create_or_update_subscription(%{
               organization_id: sub.organization_id,
               status: "past_due"
             }) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def handle_event(event_type, _payload) do
    Logger.info("Unhandled webhook event type: #{event_type}")
    :ok
  end

  defp ensure_subscription(org_id, customer_id, subscription_id, plan) do
    case Repo.get_by(Blackboex.Billing.Subscription, stripe_subscription_id: subscription_id) do
      %Blackboex.Billing.Subscription{} ->
        Logger.info(
          "checkout.session.completed: subscription #{subscription_id} already exists, skipping"
        )

        :ok

      nil ->
        case Billing.create_or_update_subscription(%{
               organization_id: org_id,
               stripe_customer_id: customer_id,
               stripe_subscription_id: subscription_id,
               plan: plan,
               status: "active"
             }) do
          {:ok, _sub} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp mark_processed(event_id, event_type) do
    %ProcessedEvent{}
    |> ProcessedEvent.changeset(%{
      event_id: event_id,
      event_type: event_type,
      processed_at: DateTime.utc_now(:second)
    })
    |> Repo.insert()
  end

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0 do
    :ok
  end

  defp validate_non_empty_binary(_value, field) do
    Logger.warning("checkout.session.completed: #{field} is missing or empty")
    {:error, :invalid_payload}
  end

  defp validate_plan(plan) when plan in @valid_plans, do: :ok

  defp validate_plan(plan) do
    Logger.warning("checkout.session.completed: invalid plan #{inspect(plan)}")
    {:error, :invalid_payload}
  end
end
