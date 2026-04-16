defmodule BlackboexWeb.PlaygroundLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, "/orgs/any/projects/any/playgrounds")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})
      %{org: org, project: project}
    end

    defp playgrounds_path(org, project),
      do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds"

    test "shows empty state when no playgrounds", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, playgrounds_path(org, project))
      assert html =~ "No playgrounds yet"
    end

    test "lists playgrounds for the project", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      playground_fixture(%{user: user, org: org, project: project, name: "My REPL"})

      {:ok, _view, html} = live(conn, playgrounds_path(org, project))
      assert html =~ "My REPL"
    end

    test "has button to create new playground", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, playgrounds_path(org, project))
      assert html =~ "New Playground"
    end

    test "opens create modal on /playgrounds/new", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/new")

      assert html =~ "Create Playground"
      assert html =~ "Name"
    end

    test "creates a playground and redirects to editor", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/new")

      view
      |> form("form[phx-submit='create_playground']", %{playground: %{name: "New REPL"}})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/playgrounds/.*/edit"
    end

    test "deletes a playground", %{conn: conn, org: org, project: project, user: user} do
      pg = playground_fixture(%{user: user, org: org, project: project, name: "Delete Me"})

      {:ok, view, _html} = live(conn, playgrounds_path(org, project))
      assert render(view) =~ "Delete Me"

      render_click(view, "delete_playground", %{"id" => pg.id})

      refute render(view) =~ "Delete Me"
    end
  end
end
