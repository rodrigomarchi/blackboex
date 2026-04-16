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

    test "redirects to first page editor when pages exist", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      page = page_fixture(%{user: user, org: org, project: project, title: "First Page"})

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages")

      assert path =~ "/pages/#{page.slug}/edit"
    end

    test "creates page and redirects when no pages exist", %{
      conn: conn,
      org: org,
      project: project
    } do
      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages")

      assert path =~ "/pages/"
      assert path =~ "/edit"
    end
  end
end
