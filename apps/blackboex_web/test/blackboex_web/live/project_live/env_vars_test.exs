defmodule BlackboexWeb.ProjectLive.EnvVarsTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  alias Blackboex.ProjectEnvVars

  setup [:register_and_log_in_user, :create_org_and_api]

  describe "mount" do
    test "empty state when project has no env vars", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      assert html =~ "No env vars yet"
    end

    test "renders tab bar with 'Env Vars' active", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      assert_has(view, ~s([data-tab="env_vars"][aria-current="page"]))
    end

    test "non-member blocked", %{org: org, project: project} do
      other_user = user_fixture()
      other_conn = build_conn() |> log_in_user(other_user)

      conn = get(other_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")
      assert conn.status in [403, 404]
    end
  end

  describe "listing" do
    test "lists only kind='env' (not llm_anthropic)", %{
      conn: conn,
      org: org,
      project: project
    } do
      _env =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          name: "FOO",
          value: "bar"
        })

      _llm =
        llm_anthropic_key_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          value: "sk-secret"
        })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      assert html =~ "FOO"
      refute html =~ "ANTHROPIC_API_KEY"
    end

    test "values are always masked, never plaintext", %{
      conn: conn,
      org: org,
      project: project
    } do
      _env =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          name: "SECRET",
          value: "super-secret-value-42"
        })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      assert html =~ "SECRET"
      assert html =~ "••••••••"
      refute html =~ "super-secret-value-42"
    end

    test "isolation: does not show other project's env vars", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      {:ok, %{project: other_project}} =
        Blackboex.Projects.create_project(org, user, %{name: "Other"})

      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        name: "OTHER_PROJ_VAR"
      })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      refute html =~ "OTHER_PROJ_VAR"
    end
  end

  describe "create" do
    test "valid form creates env var", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "create_env_var", %{
        "env_var" => %{"name" => "API_TOKEN", "value" => "abc123"}
      })

      assert ProjectEnvVars.get_env_var(project.id, "API_TOKEN")
    end

    test "invalid name (with space) returns error", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "create_env_var", %{
        "env_var" => %{"name" => "invalid name", "value" => "val"}
      })

      refute ProjectEnvVars.get_env_var(project.id, "invalid name")
    end

    test "duplicate name in same project is rejected", %{conn: conn, org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "DUPLICATED"
      })

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "create_env_var", %{
        "env_var" => %{"name" => "DUPLICATED", "value" => "second"}
      })

      # Still only one
      assert length(ProjectEnvVars.list_env_vars(project.id)) == 1
    end

    test "empty value is rejected", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "create_env_var", %{
        "env_var" => %{"name" => "EMPTY_VAL", "value" => ""}
      })

      refute ProjectEnvVars.get_env_var(project.id, "EMPTY_VAL")
    end
  end

  describe "update" do
    test "updates value of existing env var", %{conn: conn, org: org, project: project} do
      env_var =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          name: "TO_UPDATE",
          value: "old"
        })

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "open_edit_modal", %{"id" => env_var.id})

      render_hook(view, "update_env_var", %{
        "_id" => env_var.id,
        "env_var" => %{"value" => "new"}
      })

      assert {:ok, "new"} = ProjectEnvVars.get_env_value(project.id, "TO_UPDATE")
    end
  end

  describe "delete" do
    test "deletes env var after confirmation", %{conn: conn, org: org, project: project} do
      env_var =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          name: "TO_DELETE"
        })

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      render_hook(view, "open_delete_modal", %{"id" => env_var.id})
      render_hook(view, "confirm_delete_env_var", %{"id" => env_var.id})

      refute ProjectEnvVars.get_env_var(project.id, "TO_DELETE")
    end

    test "rejects deleting env var from another project", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      {:ok, %{project: other_project}} =
        Blackboex.Projects.create_project(org, user, %{name: "Other"})

      foreign =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: other_project.id,
          name: "FOREIGN"
        })

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      # Trying to delete a var from another project — must fail (not in socket.assigns.env_vars)
      render_hook(view, "confirm_delete_env_var", %{"id" => foreign.id})

      # Still exists
      assert ProjectEnvVars.get_env_var(other_project.id, "FOREIGN")
    end
  end

  describe "security" do
    test "plaintext value does not appear in initial response HTML", %{
      conn: conn,
      org: org,
      project: project
    } do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "HIDE_ME",
        value: "plaintext-should-be-hidden-abc"
      })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")

      refute html =~ "plaintext-should-be-hidden-abc"
    end
  end
end
