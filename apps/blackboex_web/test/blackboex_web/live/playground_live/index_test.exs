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

    test "redirects to first playground when playgrounds exist", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      pg = playground_fixture(%{user: user, org: org, project: project, name: "My REPL"})

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, playgrounds_path(org, project))

      assert path =~ "/playgrounds/#{pg.slug}/edit"
    end

    test "creates and redirects to new playground when none exist", %{
      conn: conn,
      org: org,
      project: project
    } do
      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, playgrounds_path(org, project))

      assert path =~ "/playgrounds/"
      assert path =~ "/edit"
    end
  end
end
