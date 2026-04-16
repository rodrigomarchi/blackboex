defmodule BlackboexWeb.PageLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, "/orgs/any/projects/any/pages")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})
      %{org: org, project: project}
    end

    defp pages_path(org, project), do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages"

    test "shows empty state when no pages", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, pages_path(org, project))
      assert html =~ "No pages yet"
    end

    test "lists pages for the project", %{conn: conn, org: org, project: project, user: user} do
      page_fixture(%{user: user, org: org, project: project, title: "Architecture Doc"})

      {:ok, _view, html} = live(conn, pages_path(org, project))
      assert html =~ "Architecture Doc"
      assert html =~ "draft"
    end

    test "has button to create new page", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, pages_path(org, project))
      assert html =~ "New Page"
    end

    test "opens create modal on /pages/new", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/new")

      assert html =~ "Create Page"
      assert html =~ "Title"
    end

    test "creates a page and redirects to editor", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/new")

      view
      |> form("form[phx-submit='create_page']", %{page: %{title: "My New Page"}})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/pages/.*/edit"
    end

    test "deletes a page", %{conn: conn, org: org, project: project, user: user} do
      page = page_fixture(%{user: user, org: org, project: project, title: "Delete Me"})

      {:ok, view, _html} = live(conn, pages_path(org, project))
      assert render(view) =~ "Delete Me"

      render_click(view, "delete_page", %{"id" => page.id})

      refute render(view) =~ "Delete Me"
    end
  end
end
