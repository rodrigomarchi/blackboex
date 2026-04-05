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

    test "displays API description when present", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _api} =
        Blackboex.Apis.create_api(%{
          name: "Described API",
          description: "Converts temperatures from Celsius to Fahrenheit",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/apis")
      assert html =~ "Converts temperatures from Celsius to Fahrenheit"
    end

    test "displays published API slug in endpoint path", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, api} =
        Blackboex.Apis.create_api(%{
          name: "Published API",
          slug: "published-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(_), do: %{ok: true}"
        })

      {:ok, _} = Blackboex.Apis.update_api(api, %{status: "published"})

      {:ok, _view, html} = live(conn, ~p"/apis")
      assert html =~ "published-api"
      assert html =~ "POST /api/"
    end

    test "shows 'Not published' for draft API", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _api} =
        Blackboex.Apis.create_api(%{
          name: "Draft Only API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/apis")
      assert html =~ "Not published"
    end
  end

  describe "search" do
    setup :register_and_log_in_user

    test "filters APIs by name", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _} =
        Blackboex.Apis.create_api(%{
          name: "Alpha API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _} =
        Blackboex.Apis.create_api(%{
          name: "Beta API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/apis")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{search: "Alpha"})

      assert html =~ "Alpha API"
      refute html =~ "Beta API"
    end

    test "shows empty state with search-specific message when no results", %{
      conn: conn,
      user: user
    } do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _} =
        Blackboex.Apis.create_api(%{
          name: "My API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/apis")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{search: "xyznonexistent"})

      assert html =~ "No APIs match your search"
      assert html =~ "Try a different query"
    end

    test "returns all APIs when search is cleared", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _} =
        Blackboex.Apis.create_api(%{
          name: "Clearable API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/apis")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{search: "xyz"})

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{search: ""})

      assert html =~ "Clearable API"
    end
  end

  describe "delete" do
    setup :register_and_log_in_user

    test "deletes an API and removes it from the list", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, api} =
        Blackboex.Apis.create_api(%{
          name: "To Delete API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/apis")
      assert render(view) =~ "To Delete API"

      html = render_click(view, "delete", %{id: api.id})

      refute html =~ "To Delete API"
      assert html =~ "API deleted"
    end

    test "shows error flash when API not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      html = render_click(view, "delete", %{id: Ecto.UUID.generate()})

      assert html =~ "API not found"
    end
  end

  describe "create modal" do
    setup :register_and_log_in_user

    test "opens create modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      html = render_click(view, "open_create_modal")

      assert html =~ "Create API"
      assert html =~ "What should this API do?"
    end

    test "closes create modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")
      html = render_click(view, "close_create_modal")

      refute html =~ "What should this API do?"
    end

    test "shows error when name is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      html =
        view
        |> form("form[phx-submit='create_api']", %{name: "", description: ""})
        |> render_submit()

      assert html =~ "Name is required"
    end

    test "shows error when description exceeds max length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      long_description = String.duplicate("x", 10_001)

      html =
        view
        |> form("form[phx-submit='create_api']", %{
          name: "Valid Name",
          description: long_description
        })
        |> render_submit()

      assert html =~ "Description too long"
    end

    test "creates API without description and redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      view
      |> form("form[phx-submit='create_api']", %{name: "New API", description: ""})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end

    test "creates API with description and redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")

      view
      |> form("form[phx-submit='create_api']", %{
        name: "Generated API",
        description: "Convert Celsius to Fahrenheit"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end
  end
end
