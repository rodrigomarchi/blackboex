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

  describe "lista membros do projeto" do
    test "mostra membros explícitos com role", %{
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

  describe "mostra membros implicitos (org owner/admin) com badge" do
    test "org admin aparece com badge de acesso implícito", %{
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

  describe "project admin pode adicionar membro da org" do
    test "adiciona membro elegível via form", %{
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

  describe "project admin pode editar role" do
    test "atualiza role de membro explícito", %{
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

  describe "project admin pode remover membro" do
    test "remove membro ao clicar em Remove", %{
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

  describe "project editor NAO pode gerenciar membros" do
    test "editor nao ve acoes de gestao", %{
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
