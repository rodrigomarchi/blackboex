defmodule BlackboexWeb.InvitationLive.AcceptTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  describe "mount with valid token" do
    setup [:create_user_and_org]

    test "renders the accept form for a new invitee", %{conn: conn, user: inviter, org: org} do
      %{raw_token: token} =
        org_invitation_fixture(%{
          organization_id: org.id,
          invited_by_id: inviter.id,
          email: "newbie@example.com"
        })

      {:ok, _lv, html} = live(conn, ~p"/invitations/#{token}")
      assert html =~ "newbie@example.com"
      assert html =~ ~s(phx-submit="accept")
    end
  end

  describe "mount with invalid token" do
    test "raises NoRouteError when token does not exist", %{conn: conn} do
      assert {:error, _} = live(conn, ~p"/invitations/nonexistent")
    end
  end

  describe "mount with expired token" do
    setup [:create_user_and_org]

    test "raises NoRouteError for an expired invite", %{conn: conn, user: inviter, org: org} do
      %{raw_token: token} =
        expired_org_invitation_fixture(%{
          organization_id: org.id,
          invited_by_id: inviter.id,
          email: "late@example.com"
        })

      assert {:error, _} = live(conn, ~p"/invitations/#{token}")
    end
  end

  describe "submit accept" do
    setup [:create_user_and_org]

    test "creates user, membership, and redirects with token", %{
      conn: conn,
      user: inviter,
      org: org
    } do
      %{raw_token: token} =
        org_invitation_fixture(%{
          organization_id: org.id,
          invited_by_id: inviter.id,
          email: "newbie@example.com"
        })

      {:ok, lv, _html} = live(conn, ~p"/invitations/#{token}")

      result =
        lv
        |> form("#accept-form",
          user: %{password: "supersecret123", password_confirmation: "supersecret123"}
        )
        |> render_submit()

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/setup/finish?token=" or redirect_path =~ "/orgs/#{org.slug}"

      assert Blackboex.Accounts.get_user_by_email("newbie@example.com")
    end

    test "rejects mismatched password confirmation", %{conn: conn, user: inviter, org: org} do
      %{raw_token: token} =
        org_invitation_fixture(%{
          organization_id: org.id,
          invited_by_id: inviter.id,
          email: "newbie@example.com"
        })

      {:ok, lv, _html} = live(conn, ~p"/invitations/#{token}")

      html =
        lv
        |> form("#accept-form",
          user: %{password: "supersecret123", password_confirmation: "different12345"}
        )
        |> render_submit()

      assert html =~ "do not match" or html =~ "must match"
    end
  end
end
