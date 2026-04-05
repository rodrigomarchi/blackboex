defmodule Blackboex.Billing.WebhookHandlerTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.{Subscription, WebhookHandler}
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org, user: user}
  end

  describe "handle_event/2 checkout.session.completed" do
    setup [:create_org]

    test "creates subscription and syncs org plan", %{org: org} do
      payload = %{
        "customer" => "cus_test123",
        "subscription" => "sub_test456",
        "metadata" => %{
          "organization_id" => org.id,
          "plan" => "pro"
        }
      }

      assert :ok = WebhookHandler.handle_event("checkout.session.completed", payload)

      sub = Billing.get_subscription(org.id)
      assert sub.plan == "pro"
      assert sub.stripe_customer_id == "cus_test123"
      assert sub.stripe_subscription_id == "sub_test456"

      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :pro
    end

    test "rejects payload with missing organization_id" do
      payload = %{
        "customer" => "cus_test123",
        "subscription" => "sub_test456",
        "metadata" => %{"plan" => "pro"}
      }

      assert {:error, :invalid_payload} =
               WebhookHandler.handle_event("checkout.session.completed", payload)
    end

    test "rejects payload with empty customer" do
      payload = %{
        "customer" => "",
        "subscription" => "sub_test456",
        "metadata" => %{"organization_id" => Ecto.UUID.generate(), "plan" => "pro"}
      }

      assert {:error, :invalid_payload} =
               WebhookHandler.handle_event("checkout.session.completed", payload)
    end

    test "rejects payload with missing subscription" do
      payload = %{
        "customer" => "cus_test123",
        "metadata" => %{"organization_id" => Ecto.UUID.generate(), "plan" => "pro"}
      }

      assert {:error, :invalid_payload} =
               WebhookHandler.handle_event("checkout.session.completed", payload)
    end

    test "rejects payload with invalid plan" do
      payload = %{
        "customer" => "cus_test123",
        "subscription" => "sub_test456",
        "metadata" => %{"organization_id" => Ecto.UUID.generate(), "plan" => "ultra"}
      }

      assert {:error, :invalid_payload} =
               WebhookHandler.handle_event("checkout.session.completed", payload)
    end
  end

  describe "handle_event/2 customer.subscription.updated" do
    setup [:create_org]

    test "updates subscription status", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          stripe_subscription_id: "sub_existing",
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      payload = %{
        "id" => "sub_existing",
        "status" => "past_due",
        "cancel_at_period_end" => true,
        "current_period_start" => 1_711_929_600,
        "current_period_end" => 1_714_521_600
      }

      assert :ok = WebhookHandler.handle_event("customer.subscription.updated", payload)

      sub = Billing.get_subscription(org.id)
      assert sub.status == "past_due"
      assert sub.cancel_at_period_end == true
    end
  end

  describe "handle_event/2 customer.subscription.deleted" do
    setup [:create_org]

    test "marks subscription as canceled and reverts to free", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          stripe_subscription_id: "sub_to_delete",
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      payload = %{"id" => "sub_to_delete"}

      assert :ok = WebhookHandler.handle_event("customer.subscription.deleted", payload)

      sub = Billing.get_subscription(org.id)
      assert sub.plan == "free"
      assert sub.status == "canceled"

      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :free
    end
  end

  describe "handle_event/2 invoice.payment_failed" do
    setup [:create_org]

    test "marks subscription as past_due", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          stripe_subscription_id: "sub_payment_fail",
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      payload = %{"subscription" => "sub_payment_fail"}

      assert :ok = WebhookHandler.handle_event("invoice.payment_failed", payload)

      sub = Billing.get_subscription(org.id)
      assert sub.status == "past_due"
    end
  end

  describe "process_event/3 idempotency" do
    setup [:create_org]

    test "processes event only once", %{org: org} do
      payload = %{
        "customer" => "cus_idem",
        "subscription" => "sub_idem",
        "metadata" => %{
          "organization_id" => org.id,
          "plan" => "pro"
        }
      }

      assert :ok =
               WebhookHandler.process_event("evt_test123", "checkout.session.completed", payload)

      assert {:error, :already_processed} =
               WebhookHandler.process_event("evt_test123", "checkout.session.completed", payload)
    end

    test "rolls back mark_processed when handle_event fails", %{org: _org} do
      # Use a nonexistent org_id so subscription insert fails with FK constraint
      nonexistent_org_id = Ecto.UUID.generate()

      payload = %{
        "customer" => "cus_rollback",
        "subscription" => "sub_rollback",
        "metadata" => %{
          "organization_id" => nonexistent_org_id,
          "plan" => "pro"
        }
      }

      assert {:error, :insert_failed} =
               WebhookHandler.process_event("evt_rollback", "checkout.session.completed", payload)

      # Verify the processed_event was rolled back — retrying should NOT return :already_processed
      # It should fail again with the same error, proving the transaction rolled back
      assert {:error, :insert_failed} =
               WebhookHandler.process_event("evt_rollback", "checkout.session.completed", payload)
    end
  end

  describe "ensure_subscription idempotency" do
    setup [:create_org]

    test "does not duplicate subscription when it already exists", %{org: org} do
      payload = %{
        "customer" => "cus_dup",
        "subscription" => "sub_dup",
        "metadata" => %{
          "organization_id" => org.id,
          "plan" => "pro"
        }
      }

      # First call creates the subscription
      assert :ok = WebhookHandler.handle_event("checkout.session.completed", payload)

      sub_before = Billing.get_subscription(org.id)
      assert sub_before.stripe_subscription_id == "sub_dup"

      # Second call with same subscription_id should be idempotent
      assert :ok = WebhookHandler.handle_event("checkout.session.completed", payload)

      # Verify no duplicate was created
      count =
        Blackboex.Repo.aggregate(
          Ecto.Query.from(s in Subscription,
            where: s.stripe_subscription_id == "sub_dup"
          ),
          :count
        )

      assert count == 1
    end
  end
end
