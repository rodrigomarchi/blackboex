defmodule BlackboexWeb.ProjectLive.ApiKeysTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  alias Blackboex.Apis.Keys

  setup [:register_and_log_in_user, :create_org_and_api]

  describe "mount" do
    test "renders tab bar with 'API Keys' active", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      assert_has(view, ~s([data-role="project-settings-tabs"]))
      assert_has(view, ~s([data-tab="api_keys"][aria-current="page"]))
    end

    test "empty state when project has no keys", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      assert html =~ "No API keys yet"
    end

    test "non-member forbidden", %{org: org, project: project} do
      other_user = user_fixture()
      other_conn = build_conn() |> log_in_user(other_user)

      conn = get(other_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")
      # 404 from SetOrganizationFromUrl (org not visible) or 403 from SetProjectFromUrl
      assert conn.status in [403, 404]
    end
  end

  describe "listing" do
    test "only shows keys for the current project", %{
      conn: conn,
      user: user,
      org: org,
      project: project,
      api: api
    } do
      {:ok, _plain, project_key} =
        Keys.create_key(api, %{
          label: "Project Key",
          organization_id: org.id,
          project_id: project.id
        })

      # Second project in same org
      {:ok, %{project: other_project}} =
        Blackboex.Projects.create_project(org, user, %{name: "Other Project"})

      other_api =
        api_fixture(%{user: user, org: org, project: other_project, name: "Other API"})

      {:ok, _plain2, other_key} =
        Keys.create_key(other_api, %{
          label: "Other Key",
          organization_id: org.id,
          project_id: other_project.id
        })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      assert html =~ project_key.key_prefix
      refute html =~ other_key.key_prefix
    end

    test "revoked key shows 'Revoked' badge", %{
      conn: conn,
      org: org,
      project: project,
      api: api
    } do
      {:ok, _plain, key} =
        Keys.create_key(api, %{
          label: "Revoked",
          organization_id: org.id,
          project_id: project.id
        })

      {:ok, _} = Keys.revoke_key(key)

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      assert html =~ "Revoked"
    end
  end

  describe "create" do
    test "plaintext shown once after creation", %{
      conn: conn,
      org: org,
      project: project,
      api: api
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      html = render_hook(view, "create_key", %{"api_id" => api.id, "label" => "My Key"})

      # Plain key banner visible once
      assert html =~ "Copy this key now"
      assert html =~ "bb_live_"
    end

    test "key appears in list after creation", %{
      conn: conn,
      org: org,
      project: project,
      api: api
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      render_hook(view, "create_key", %{
        "api_id" => api.id,
        "label" => "Unique-Label-#{System.unique_integer([:positive])}"
      })

      # DB should have 1 key for this project
      keys = Keys.list_keys_for_project(project.id)
      assert length(keys) == 1
    end

    test "create_key with API not in this project is rejected", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      {:ok, %{project: other_project}} =
        Blackboex.Projects.create_project(org, user, %{name: "Other"})

      other_api =
        api_fixture(%{user: user, org: org, project: other_project, name: "Foreign"})

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      html = render_hook(view, "create_key", %{"api_id" => other_api.id, "label" => "X"})

      # Error message flashed (cross-project rejected)
      assert html =~ "does not belong to this project" or html =~ "Not authorized" or
               html =~ "API not found"

      # No plaintext banner
      refute html =~ "Copy this key now"
    end
  end

  describe "navigation" do
    test "link to key details goes to project-scoped URL", %{
      conn: conn,
      org: org,
      project: project,
      api: api
    } do
      {:ok, _plain, key} =
        Keys.create_key(api, %{
          label: "Link",
          organization_id: org.id,
          project_id: project.id
        })

      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")

      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/api-keys/#{key.id}"
    end
  end
end
