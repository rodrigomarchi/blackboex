defmodule BlackboexWeb.BillingLive.ManageTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Blackboex.Billing.Subscription
  alias Blackboex.Organizations

  @moduletag :liveview

  setup :register_and_log_in_user

  test "shows no subscription message when none exists", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing/manage")

    assert html =~ "don&#39;t have an active subscription"
    assert html =~ "View Plans"
  end

  test "shows subscription status when subscription exists", %{conn: conn, user: user} do
    [org] = Organizations.list_user_organizations(user)

    {:ok, _sub} =
      %Subscription{}
      |> Subscription.changeset(%{
        organization_id: org.id,
        stripe_customer_id: "cus_test",
        plan: "pro",
        status: "active",
        current_period_start: ~U[2026-03-01 00:00:00Z],
        current_period_end: ~U[2026-04-01 00:00:00Z]
      })
      |> Blackboex.Repo.insert()

    {:ok, _lv, html} = live(conn, ~p"/billing/manage")

    assert html =~ "pro"
    assert html =~ "active"
    assert html =~ "Manage Subscription"
    assert html =~ "Change Plan"
  end
end
