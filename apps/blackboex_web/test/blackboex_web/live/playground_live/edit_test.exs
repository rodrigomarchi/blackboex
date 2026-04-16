defmodule BlackboexWeb.PlaygroundLive.EditTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, "/orgs/any/projects/any/playgrounds/any/edit")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})

      playground =
        playground_fixture(%{user: user, org: org, project: project, name: "Test REPL"})

      %{org: org, project: project, playground: playground}
    end

    defp edit_path(org, project, playground) do
      ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/#{playground.slug}/edit"
    end

    test "renders playground editor", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, _view, html} = live(conn, edit_path(org, project, playground))
      assert html =~ "Test REPL"
      assert html =~ "Run"
    end

    test "saves playground code via save_code event", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))

      # Simulate CodeMirror updating the code
      render_click(view, "update_code", %{"value" => "1 + 1"})
      render_click(view, "save_code")

      assert render(view) =~ "Saved"
    end

    test "redirects for invalid slug", %{conn: conn, org: org, project: project} do
      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => "Playground not found"}}}} =
               live(
                 conn,
                 ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/invalid-slug/edit"
               )

      assert path =~ "/playgrounds"
    end
  end
end
