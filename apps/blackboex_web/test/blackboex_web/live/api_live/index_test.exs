defmodule BlackboexWeb.ApiLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/apis")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "lists APIs for the current org", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _api} =
        Blackboex.Apis.create_api(%{
          name: "My Test API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/apis")
      assert html =~ "My Test API"
      assert html =~ "draft"
    end

    test "shows empty state when no APIs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/apis")
      assert html =~ "No APIs"
    end

    test "has button to create new API", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      assert has_element?(view, "button[phx-click='open_create_modal']")
    end
  end
end
