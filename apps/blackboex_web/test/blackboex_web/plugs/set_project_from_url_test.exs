defmodule BlackboexWeb.Plugs.SetProjectFromUrlTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Projects
  alias BlackboexWeb.Plugs.SetProjectFromUrl
  alias BlackboexWeb.UserAuth

  @moduletag :unit

  setup :register_and_log_in_user

  defp build_conn_with_project_scope(conn, user, org, project_slug) do
    membership = Organizations.get_user_membership(org, user)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    conn
    |> UserAuth.fetch_current_scope_for_user([])
    |> Plug.Conn.put_private(:phoenix_format, "json")
    |> Plug.Conn.assign(:current_scope, scope)
    |> Map.put(:params, %{"org_slug" => org.slug, "project_slug" => project_slug})
    |> SetProjectFromUrl.call([])
  end

  describe "call/2 — SetProjectFromUrl" do
    test "sets scope with org + project + memberships for org owner", %{conn: conn, user: user} do
      {:ok, %{organization: org}} =
        Organizations.create_organization(user, %{name: "My Org"})

      project = Projects.get_default_project(org.id)
      conn = build_conn_with_project_scope(conn, user, org, project.slug)

      scope = conn.assigns.current_scope
      assert scope.organization.id == org.id
      assert scope.project.id == project.id
      # org owners get nil project_membership (implicit access)
      assert scope.project_membership == nil
      refute conn.halted
    end

    test "returns 404 for invalid project_slug", %{conn: conn, user: user} do
      {:ok, %{organization: org}} =
        Organizations.create_organization(user, %{name: "My Org"})

      conn = build_conn_with_project_scope(conn, user, org, "nonexistent-project")

      assert conn.status == 404
      assert conn.halted
    end

    test "returns 403 for org member without project access", %{conn: conn, user: user} do
      owner = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(owner, %{name: "My Org"})

      # Add user as a regular member (not owner/admin)
      {:ok, _membership} =
        Organizations.add_member(org, user, :member)

      project = Projects.get_default_project(org.id)

      # User has no project membership
      member_membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, member_membership)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Plug.Conn.assign(:current_scope, scope)
        |> Map.put(:params, %{"org_slug" => org.slug, "project_slug" => project.slug})
        |> SetProjectFromUrl.call([])

      assert conn.status == 403
      assert conn.halted
    end

    test "org admin gets implicit project access without explicit membership", %{
      conn: conn,
      user: _owner_user
    } do
      # Create a separate admin user
      admin_user = user_fixture()
      owner_user = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(owner_user, %{name: "Admin Org"})

      {:ok, _membership} = Organizations.add_member(org, admin_user, :admin)

      project = Projects.get_default_project(org.id)
      admin_membership = Organizations.get_user_membership(org, admin_user)
      scope = Scope.for_user(admin_user) |> Scope.with_organization(org, admin_membership)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Plug.Conn.assign(:current_scope, scope)
        |> Map.put(:params, %{"org_slug" => org.slug, "project_slug" => project.slug})
        |> SetProjectFromUrl.call([])

      assert conn.assigns.current_scope.project.id == project.id
      assert conn.assigns.current_scope.project_membership == nil
      refute conn.halted
    end

    test "passes through when no org in scope", %{conn: conn} do
      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Map.put(:params, %{"org_slug" => "any", "project_slug" => "any"})
        |> SetProjectFromUrl.call([])

      refute conn.halted
    end
  end
end
