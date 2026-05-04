defmodule BlackboexWeb.PageLive.EditTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Pages

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

    # ── Mount & Render ────────────────────────────────────────

    test "renders page editor with tiptap container", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ "TiptapEditor"
      assert html =~ "page-tiptap-editor"
    end

    test "renders page title", %{conn: conn, org: org, project: project, page: page} do
      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ "Test Page"
    end

    test "renders status badge", %{conn: conn, org: org, project: project, page: page} do
      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ "draft"
    end

    # ── Content Events (JS Hook) ─────────────────────────────

    test "update_content saves markdown via hook event", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))

      render_click(view, "update_content", %{"value" => "# Hello World"})

      updated = Pages.get_page(project.id, page.id)
      assert updated.content == "# Hello World"
    end

    test "update_content with empty string saves empty content", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, _} = Pages.update_page(page, %{content: "some content"})
      {:ok, view, _html} = live(conn, edit_path(org, project, page))

      render_click(view, "update_content", %{"value" => ""})

      updated = Pages.get_page(project.id, page.id)
      assert updated.content == ""
    end

    # ── Title ────────────────────────────────────────────────

    test "saves title change", %{conn: conn, org: org, project: project, page: page} do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))

      view
      |> form(~s(form[phx-submit="save_title"]), %{"page" => %{"title" => "New Title"}})
      |> render_submit()

      assert render(view) =~ "Title saved"
      assert Pages.get_page(project.id, page.id).title == "New Title"
    end

    # ── Status ───────────────────────────────────────────────

    test "toggles page status from draft to published", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, page))
      assert render(view) =~ "draft"

      render_click(view, "toggle_status")

      assert render(view) =~ "published"
    end

    test "toggles page status from published to draft", %{
      conn: conn,
      org: org,
      project: project,
      page: page
    } do
      {:ok, _} = Pages.update_page(page, %{status: "published"})
      {:ok, view, _html} = live(conn, edit_path(org, project, page))
      assert render(view) =~ "published"

      render_click(view, "toggle_status")

      assert render(view) =~ "draft"
    end

    # ── Edge Cases ───────────────────────────────────────────

    test "redirects for invalid slug", %{conn: conn, org: org, project: project} do
      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => "Page not found"}}}} =
               live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/invalid-slug/edit")

      assert path =~ "/pages"
    end

    test "sidebar in :editor layout renders SidebarTreeComponent",
         %{conn: conn, org: org, project: project, page: page} do
      {:ok, _view, html} = live(conn, edit_path(org, project, page))
      assert html =~ ~s(data-testid="sidebar-tree")
      assert length(:binary.matches(html, ~s(data-testid="sidebar-tree"))) == 1
    end
  end
end
