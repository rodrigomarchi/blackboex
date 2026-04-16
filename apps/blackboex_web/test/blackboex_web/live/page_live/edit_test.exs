defmodule BlackboexWeb.PageLive.EditTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, "/orgs/any/projects/any/pages/any/edit")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})
      page = page_fixture(%{user: user, org: org, project: project, title: "Test Page"})
      %{org: org, project: project, page: page}
    end

    defp edit_path(org, project, page) do
      ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/#{page.slug}/edit"
    end

    test "renders page editor", %{conn: conn, org: org, project: project, page: page} do
      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ "Test Page"
      assert html =~ "draft"
    end

    test "saves page title", %{conn: conn, org: org, project: project, page: page} do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))

      view
      |> form("form[phx-submit='save']", %{page: %{title: "Updated Title"}})
      |> render_submit()

      assert render(view) =~ "Page saved"
    end

    test "updates content via CodeMirror event", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))

      render_click(view, "update_content", %{"value" => "# New Content"})

      # Preview should show rendered markdown
      assert render(view) =~ "<h1>"
    end

    test "toggles page status", %{conn: conn, org: org, project: project, page: page} do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))
      assert render(view) =~ "draft"

      render_click(view, "toggle_status")

      assert render(view) =~ "published"
    end

    test "redirects for invalid slug", %{conn: conn, org: org, project: project} do
      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => "Page not found"}}}} =
               live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/invalid-slug/edit")

      assert path =~ "/pages"
    end

    test "renders markdown preview", %{conn: conn, org: org, project: project, page: page} do
      {:ok, page} = Blackboex.Pages.update_page(page, %{content: "**bold text**"})

      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ "<strong>bold text</strong>"
    end
  end
end
