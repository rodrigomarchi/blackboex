defmodule BlackboexWeb.OrgMemberLiveTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  setup [:register_and_log_in_user, :create_org]

  setup %{org: org} do
    member = user_fixture()
    membership = org_member_fixture(%{org: org, user: member, role: :member})
    %{member: member, membership: membership}
  end

  describe "lista membros da org com roles" do
    test "mostra membros com email e role", %{conn: conn, org: org, member: member} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/members")

      assert html =~ member.email
      assert html =~ "member"
    end
  end

  describe "owner pode editar role de membro" do
    test "atualiza role via inline select", %{conn: conn, org: org, membership: membership} do
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      lv
      |> form("#role-form-#{membership.id}", %{membership_id: membership.id, role: "admin"})
      |> render_change()

      html = render(lv)
      assert html =~ "admin"
    end
  end

  describe "owner pode remover membro" do
    test "remove membro ao clicar em Remove", %{
      conn: conn,
      org: org,
      membership: membership,
      member: member
    } do
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      lv
      |> element("[phx-click='remove_member'][phx-value-id='#{membership.id}']")
      |> render_click()

      html = render(lv)
      refute html =~ member.email
    end
  end

  describe "NAO pode remover ultimo owner" do
    test "exibe erro ao tentar remover unico owner", %{conn: conn, org: org, user: owner} do
      owner_membership = Blackboex.Organizations.get_user_membership(org, owner)
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      lv
      |> element("[phx-click='remove_member'][phx-value-id='#{owner_membership.id}']")
      |> render_click()

      assert has_element?(lv, "#flash-error", "Cannot remove the last owner")
    end
  end

  describe "member NAO pode editar roles" do
    test "membro sem privilegio nao ve botoes de edicao", %{
      conn: conn,
      org: org,
      member: member
    } do
      member_conn = log_in_user(conn, member)
      {:ok, _lv, html} = live(member_conn, ~p"/orgs/#{org.slug}/members")

      refute html =~ "role-form"
      refute html =~ "phx-click=\"remove_member\""
    end
  end

  describe "invite member" do
    test "owner sees the Invite member button", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/members")
      assert html =~ "Invite member"
    end

    test "non-owner does not see the button", %{conn: conn, org: org, member: member} do
      member_conn = log_in_user(conn, member)
      {:ok, _lv, html} = live(member_conn, ~p"/orgs/#{org.slug}/members")
      refute html =~ "Invite member"
    end

    test "submitting the invite form creates an invitation and shows success flash", %{
      conn: conn,
      org: org
    } do
      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/members")
      lv |> element("button", "Invite member") |> render_click()

      html =
        lv
        |> form("#invite-form",
          invitation: %{email: "newbie@example.com", role: "member"}
        )
        |> render_submit()

      assert html =~ "Invitation sent" or html =~ "invitation"

      assert Blackboex.Repo.get_by(Blackboex.Organizations.Invitation,
               organization_id: org.id,
               email: "newbie@example.com"
             )
    end
  end
end
