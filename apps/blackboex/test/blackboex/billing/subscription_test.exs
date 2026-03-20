defmodule Blackboex.Billing.SubscriptionTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Billing.Subscription
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org}
  end

  defp valid_attrs(org) do
    %{
      organization_id: org.id,
      stripe_customer_id: "cus_test123",
      stripe_subscription_id: "sub_test456",
      plan: "pro",
      status: "active",
      current_period_start: ~U[2026-03-01 00:00:00Z],
      current_period_end: ~U[2026-04-01 00:00:00Z]
    }
  end

  describe "changeset/2" do
    setup [:create_org]

    test "valid changeset with all fields", %{org: org} do
      changeset = Subscription.changeset(%Subscription{}, valid_attrs(org))
      assert changeset.valid?
    end

    test "requires organization_id" do
      changeset = Subscription.changeset(%Subscription{}, %{plan: "free", status: "active"})
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires plan", %{org: org} do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          organization_id: org.id,
          status: "active",
          plan: "invalid"
        })

      assert %{plan: ["is invalid"]} = errors_on(changeset)
    end

    test "validates plan is one of free, pro, enterprise", %{org: org} do
      for plan <- ~w(free pro enterprise) do
        changeset = Subscription.changeset(%Subscription{}, %{valid_attrs(org) | plan: plan})
        assert changeset.valid?, "expected plan '#{plan}' to be valid"
      end

      changeset = Subscription.changeset(%Subscription{}, %{valid_attrs(org) | plan: "invalid"})
      assert %{plan: ["is invalid"]} = errors_on(changeset)
    end

    test "validates status is one of active, past_due, canceled, trialing", %{org: org} do
      for status <- ~w(active past_due canceled trialing) do
        changeset = Subscription.changeset(%Subscription{}, %{valid_attrs(org) | status: status})
        assert changeset.valid?, "expected status '#{status}' to be valid"
      end

      changeset =
        Subscription.changeset(%Subscription{}, %{valid_attrs(org) | status: "invalid"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "enforces unique organization_id", %{org: org} do
      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(valid_attrs(org))
        |> Repo.insert()

      {:error, changeset} =
        %Subscription{}
        |> Subscription.changeset(valid_attrs(org))
        |> Repo.insert()

      assert %{organization_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "validates stripe_customer_id max length", %{org: org} do
      attrs = %{valid_attrs(org) | stripe_customer_id: String.duplicate("a", 256)}
      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{stripe_customer_id: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end
  end
end
