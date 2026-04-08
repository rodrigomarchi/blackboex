defmodule BlackboexWeb.FlowLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/flows")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "lists flows for the current org", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _flow} =
        Blackboex.Flows.create_flow(%{
          name: "My Test Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "My Test Flow"
      assert html =~ "draft"
    end

    test "shows empty state when no flows", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "No flows"
    end

    test "has button to create new flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/flows")
      assert has_element?(view, "button[phx-click='open_create_modal']")
    end

    test "displays flow description when present", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _flow} =
        Blackboex.Flows.create_flow(%{
          name: "Described Flow",
          description: "Processes incoming webhooks",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "Processes incoming webhooks"
    end

    test "deletes a flow", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Delete Me",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows")
      assert render(view) =~ "Delete Me"

      view
      |> element("button[phx-click='delete'][phx-value-id='#{flow.id}']")
      |> render_click()

      refute render(view) =~ "Delete Me"
    end

    test "searches flows by name", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _} =
        Blackboex.Flows.create_flow(%{
          name: "Payment Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _} =
        Blackboex.Flows.create_flow(%{
          name: "Auth Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows")
      assert render(view) =~ "Payment Flow"
      assert render(view) =~ "Auth Flow"

      view
      |> form("form", %{search: "Payment"})
      |> render_change()

      assert render(view) =~ "Payment Flow"
      refute render(view) =~ "Auth Flow"
    end
  end
end
