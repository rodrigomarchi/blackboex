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

    test "renders playground editor with PlaygroundEditor hook", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, _view, html} = live(conn, edit_path(org, project, playground))
      assert html =~ ~s(phx-hook="PlaygroundEditor")
      assert html =~ ~s(data-language="elixir")
    end

    test "save_code persists code to database", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))

      render_click(view, "update_code", %{"value" => "1 + 1"})
      render_click(view, "save_code")

      updated = Blackboex.Playgrounds.get_playground(project.id, playground.id)
      assert updated.code == "1 + 1"
    end

    test "autocomplete event returns without crashing", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))
      assert render_click(view, "autocomplete", %{"hint" => "Enum."})
    end

    test "autocomplete for blocked module does not crash", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))
      assert render_click(view, "autocomplete", %{"hint" => "System."})
    end

    test "format_code event does not crash for valid code", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))
      render_click(view, "update_code", %{"value" => "Enum.map(   [1,2,3],   &(&1*2)   )"})
      assert render_click(view, "format_code")
    end

    test "format_code event handles invalid syntax gracefully", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))
      render_click(view, "update_code", %{"value" => "def foo("})
      html = render_click(view, "format_code")
      assert html =~ "Format error"
    end

    # ── Sidebar tree tests ────────────────────────────────────

    test "renders sidebar with playground list", %{
      conn: conn,
      org: org,
      project: project,
      user: user,
      playground: playground
    } do
      _other = playground_fixture(%{user: user, org: org, project: project, name: "Other REPL"})

      {:ok, _view, html} = live(conn, edit_path(org, project, playground))
      assert html =~ "Playgrounds"
      assert html =~ "Test REPL"
      assert html =~ "Other REPL"
    end

    test "sidebar highlights current playground", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, _view, html} = live(conn, edit_path(org, project, playground))
      # Current playground should have selected state (bg-accent)
      assert html =~ "bg-accent"
    end

    test "select_playground navigates to another playground", %{
      conn: conn,
      org: org,
      project: project,
      user: user,
      playground: playground
    } do
      other = playground_fixture(%{user: user, org: org, project: project, name: "Other REPL"})

      {:ok, view, _html} = live(conn, edit_path(org, project, playground))

      view
      |> element("[phx-click='select_playground'][phx-value-slug='#{other.slug}']")
      |> render_click()

      assert_redirected(
        view,
        ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/#{other.slug}/edit"
      )
    end

    test "new_playground creates and navigates to new playground", %{
      conn: conn,
      org: org,
      project: project,
      playground: playground
    } do
      {:ok, view, _html} = live(conn, edit_path(org, project, playground))
      view |> element("button[phx-click='new_playground']") |> render_click()

      # Should navigate to the new playground — get the redirect path
      {path, _flash} = assert_redirect(view)
      assert path =~ "/playgrounds/"
      assert path =~ "/edit"
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
