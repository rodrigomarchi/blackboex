defmodule BlackboexWeb.ApiLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

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
          user_id: user.id
        })

      Blackboex.Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(_), do: %{ok: true}", file_type: "source"}
      ])

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
      render_click(view, "switch_to_description")

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
      render_click(view, "switch_to_description")

      view
      |> form("form[phx-submit='create_api']", %{name: "New API", description: ""})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end

    test "creates API with description and redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")

      render_click(view, "open_create_modal")
      render_click(view, "switch_to_description")

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

  describe "template selector in create modal" do
    setup :register_and_log_in_user

    test "modal shows template section with category tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      html = render_click(view, "open_create_modal")

      # Should show category tabs for templates
      assert html =~ "AI Agent Tools"
    end

    test "modal opens in template mode by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      html = render_click(view, "open_create_modal")

      # Template cards should be visible (cotacao-frete is the first template)
      assert html =~ "Cotação de Frete"
    end

    test "selecting a template pre-fills the name and shows template preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      html = render_click(view, "select_template", %{"id" => "cotacao-frete"})

      # Template name should appear in the preview section
      assert html =~ "Cotação de Frete"
    end

    test "clearing a selected template removes template preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      render_click(view, "select_template", %{"id" => "cotacao-frete"})
      html = render_click(view, "clear_template")

      # After clearing, the template preview should be gone and description field should be back
      refute html =~ "phx-click=\"clear_template\""
    end

    test "switching to description mode shows description field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      html = render_click(view, "switch_to_description")

      assert html =~ "What should this API do?"
    end

    test "switching back to template mode shows template grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      render_click(view, "switch_to_description")
      html = render_click(view, "switch_to_template")

      assert html =~ "AI Agent Tools"
    end

    test "creating API from template redirects to editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      render_click(view, "select_template", %{"id" => "cotacao-frete"})

      view
      |> form("form[phx-submit='create_api']", %{name: "My Frete API", description: ""})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/apis/.+/edit"
    end

    test "API created from template has compiled status and template_id", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/apis")
      render_click(view, "open_create_modal")

      render_click(view, "select_template", %{"id" => "cotacao-frete"})

      view
      |> form("form[phx-submit='create_api']", %{name: "My Frete API", description: ""})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      api_id = path |> String.split("/") |> Enum.at(-2)

      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      api = Blackboex.Apis.get_api(org.id, api_id)

      assert api.status == "compiled"
      assert api.template_id == "cotacao-frete"
    end
  end
end
