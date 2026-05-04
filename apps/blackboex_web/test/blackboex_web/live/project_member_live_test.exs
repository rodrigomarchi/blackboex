defmodule BlackboexWeb.ProjectMemberLiveTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  setup [:register_and_log_in_user, :create_org]

  setup %{org: org, project: project} do
    # Add a regular org member with explicit project membership
    project_member = user_fixture()
    org_member_fixture(%{org: org, user: project_member, role: :member})

    project_membership =
      project_membership_fixture(%{project: project, user: project_member, role: :editor})

    # Add an org admin (implicit project access)
    org_admin = user_fixture()
    org_member_fixture(%{org: org, user: org_admin, role: :admin})

    %{
      project_member: project_member,
      project_membership: project_membership,
      org_admin: org_admin
    }
  end

  describe "lists project members" do
    test "shows explicit members with role", %{
      conn: conn,
      org: org,
      project: project,
      project_member: pm
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      assert html =~ pm.email
      assert html =~ "editor"
    end
  end

  describe "shows implicit members (org owner/admin) with badge" do
    test "org admin appears with implicit access badge", %{
      conn: conn,
      org: org,
      project: project,
      org_admin: admin
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      assert html =~ admin.email
      assert html =~ "implicit"
    end
  end

  describe "project admin can add org member" do
    test "adds eligible member through form", %{
      conn: conn,
      org: org,
      project: project
    } do
      # Create a new org member not yet in project
      new_member = user_fixture()
      org_member_fixture(%{org: org, user: new_member, role: :member})

      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      lv
      |> form("#add-member-form", %{user_id: new_member.id, role: "viewer"})
      |> render_submit()

      html = render(lv)
      assert html =~ new_member.email
    end
  end

  describe "project admin can edit role" do
    test "updates explicit member role", %{
      conn: conn,
      org: org,
      project: project,
      project_membership: pm
    } do
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      lv
      |> form("#role-form-#{pm.id}", %{membership_id: pm.id, role: "admin"})
      |> render_change()

      html = render(lv)
      assert html =~ "admin"
    end
  end

  describe "project admin can remove member" do
    test "removes member when clicking Remove", %{
      conn: conn,
      org: org,
      project: project,
      project_membership: pm
    } do
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      lv
      |> element("[phx-click='remove_member'][phx-value-id='#{pm.id}']")
      |> render_click()

      # Button for that membership should no longer exist
      refute has_element?(lv, "[phx-click='remove_member'][phx-value-id='#{pm.id}']")
    end
  end

  describe "project editor cannot manage members" do
    test "editor does not see management actions", %{
      conn: conn,
      org: org,
      project: project,
      project_member: editor
    } do
      editor_conn = log_in_user(conn, editor)

      {:ok, _lv, html} =
        live(editor_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/members")

      refute html =~ "role-form"
      refute html =~ "add-member-form"
      refute html =~ "phx-click=\"remove_member\""
    end
  end
end
