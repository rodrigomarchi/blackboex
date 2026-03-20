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
  end
end
