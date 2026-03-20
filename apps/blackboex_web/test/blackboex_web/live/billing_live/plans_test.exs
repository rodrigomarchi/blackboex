defmodule BlackboexWeb.BillingLive.PlansTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
end
