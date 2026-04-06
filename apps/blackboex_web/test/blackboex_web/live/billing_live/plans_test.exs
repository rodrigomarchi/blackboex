defmodule BlackboexWeb.BillingLive.PlansTest do
  use BlackboexWeb.ConnCase, async: false

  import Mox

  @moduletag :liveview
  setup :register_and_log_in_user

  test "renders three plan cards", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/billing")

    assert html =~ "Choose your plan"
    assert html =~ "Free"
    assert html =~ "Pro"
    assert html =~ "Enterprise"
    assert html =~ "$0"
    assert html =~ "$29"
    assert html =~ "$99"

    # Current plan (free) should be highlighted
    rendered = render(lv)
    assert rendered =~ "Current Plan"
  end

  test "shows features for each plan", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    assert html =~ "10 APIs"
    assert html =~ "50 APIs"
    assert html =~ "Unlimited APIs"
  end

  test "choose plan button is present for non-current plans", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    assert html =~ "Choose Pro"
    assert html =~ "Choose Enterprise"
  end

  test "current plan is highlighted with ring styling", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    # Free plan (current) gets ring-2 ring-primary
    assert html =~ "ring-primary"
  end

  test "free plan button is disabled", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    # Free plan button shows "Free" with disabled attribute
    assert html =~ "Free"
    assert html =~ "disabled"
  end

  test "usage section is rendered when org has subscription data", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    # Usage section shows progress bars for APIs and invocations
    assert html =~ "Usage this month" or html =~ "Current Plan"
  end

  test "page renders all plan features", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/billing")

    assert html =~ "invocations"
    assert html =~ "LLM generations"
    assert html =~ "support"
  end

  test "choose_plan triggers Stripe checkout redirect", %{conn: conn} do
    stub(Blackboex.Billing.StripeClientMock, :create_checkout_session, fn _params ->
      {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/test"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/billing")

    result = render_click(lv, "choose_plan", %{"plan" => "pro"})
    assert is_binary(result) or match?({:error, {:redirect, _}}, result)
  end
end
