defmodule BlackboexWeb.ApiLive.NewTest do
  use BlackboexWeb.ConnCase, async: false

  alias BlackboexWeb.ApiLive.New

  @moduletag :liveview

  describe "render" do
    test "renders an empty div" do
      assigns = %{__changed__: nil}
      html = Phoenix.LiveViewTest.render_component(&New.render/1, assigns)
      assert html =~ "<div"
    end
  end

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/apis/new")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "redirects to /apis index", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/apis"}}} = live(conn, ~p"/apis/new")
    end
  end

  describe "creation modal on index" do
    setup :register_and_log_in_user

    test "opens and closes create modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      html = render_click(view, "open_create_modal")

      assert html =~ "Create API"
      assert html =~ "What should this API do?"

      html =
        view
        |> element("button", "Cancel")
        |> render_click()

      refute html =~ "What should this API do?"
    end

    test "shows error on empty name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      html =
        view
        |> form("form[phx-submit='create_api']", %{name: "", description: ""})
        |> render_submit()

      assert html =~ "Name is required"
    end

    test "creates API without description and redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      view
      |> form("form[phx-submit='create_api']", %{name: "Test API", description: ""})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end

    test "creates API with description and redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      view
      |> form("form[phx-submit='create_api']", %{
        name: "My API",
        description: "Convert Celsius to Fahrenheit"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end
  end
end
