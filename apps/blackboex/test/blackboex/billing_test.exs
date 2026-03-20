defmodule Blackboex.BillingTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.Subscription
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures
  import Mox

  @moduletag :unit

  setup :verify_on_exit!

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org, user: user}
  end

  describe "get_subscription/1" do
    setup [:create_org]

    test "returns nil when no subscription exists", %{org: org} do
      assert Billing.get_subscription(org.id) == nil
    end

    test "returns subscription when it exists", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      sub = Billing.get_subscription(org.id)
      assert sub.plan == "pro"
      assert sub.organization_id == org.id
    end
  end

  describe "create_checkout_session/4" do
    setup [:create_org]

    test "calls Stripe client and returns URL", %{org: org} do
      Blackboex.Billing.StripeClientMock
      |> expect(:create_checkout_session, fn params ->
        assert params.price_id == "price_pro_monthly"
        assert params.metadata["organization_id"] == org.id
        assert params.metadata["plan"] == "pro"
        {:ok, %{id: "cs_test123", url: "https://checkout.stripe.com/test"}}
      end)

      assert {:ok, %{url: url}} =
               Billing.create_checkout_session(
                 org,
                 "pro",
                 "https://example.com/success",
                 "https://example.com/cancel"
               )

      assert url == "https://checkout.stripe.com/test"
    end

    test "returns error when Stripe fails", %{org: org} do
      Blackboex.Billing.StripeClientMock
      |> expect(:create_checkout_session, fn _params ->
        {:error, "stripe_error"}
      end)

      assert {:error, "stripe_error"} =
               Billing.create_checkout_session(
                 org,
                 "pro",
                 "https://example.com/success",
                 "https://example.com/cancel"
               )
    end
  end

  describe "create_portal_session/2" do
    setup [:create_org]

    test "returns portal URL when subscription exists", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          stripe_customer_id: "cus_test123",
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      Blackboex.Billing.StripeClientMock
      |> expect(:create_portal_session, fn "cus_test123", return_url ->
        assert return_url == "https://example.com/billing"
        {:ok, %{url: "https://billing.stripe.com/session/test"}}
      end)

      assert {:ok, %{url: url}} =
               Billing.create_portal_session(org, "https://example.com/billing")

      assert url == "https://billing.stripe.com/session/test"
    end

    test "returns error when no subscription exists", %{org: org} do
      assert {:error, :no_subscription} =
               Billing.create_portal_session(org, "https://example.com/billing")
    end
  end

  describe "create_or_update_subscription/1" do
    setup [:create_org]

    test "creates new subscription and syncs org plan", %{org: org} do
      attrs = %{
        organization_id: org.id,
        stripe_customer_id: "cus_test",
        stripe_subscription_id: "sub_test",
        plan: "pro",
        status: "active"
      }

      assert {:ok, sub} = Billing.create_or_update_subscription(attrs)
      assert sub.plan == "pro"
      assert sub.organization_id == org.id

      # Verify org plan was synced
      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :pro
    end

    test "updates existing subscription", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          plan: "pro",
          status: "active"
        })
        |> Repo.insert()

      attrs = %{
        organization_id: org.id,
        plan: "enterprise",
        status: "active"
      }

      assert {:ok, sub} = Billing.create_or_update_subscription(attrs)
      assert sub.plan == "enterprise"

      # Verify org plan was synced
      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :enterprise
    end
  end
end
