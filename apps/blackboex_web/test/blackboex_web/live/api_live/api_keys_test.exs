defmodule BlackboexWeb.ApiLive.ApiKeysTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis.Keys

  setup [:register_and_log_in_user, :create_org_and_api]

  describe "API keys lifecycle" do
    test "create -> rotate -> revoke", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/keys?org=#{org.id}")

      assert html =~ "No API keys yet"

      # Create a key
      html = lv |> element(~s(button[phx-click="create_key"])) |> render_click()

      # Should show the plain key flash
      assert html =~ "Copy this key now"
      assert html =~ "bb_live_"

      # Key should appear in the list as Active
      assert html =~ "Active"

      # Verify key was created in DB
      keys = Keys.list_keys(api.id)
      assert length(keys) == 1
      first_key = hd(keys)
      assert is_nil(first_key.revoked_at)

      # Rotate the key
      html =
        lv
        |> element(~s(button[phx-click="rotate_key"][phx-value-key-id="#{first_key.id}"]))
        |> render_click()

      # Should show new plain key
      assert html =~ "Copy this key now"

      # Old key should be revoked, new key active
      keys = Keys.list_keys(api.id)
      assert length(keys) == 2

      revoked_keys = Enum.filter(keys, & &1.revoked_at)
      active_keys = Enum.reject(keys, & &1.revoked_at)
      assert length(revoked_keys) == 1
      assert length(active_keys) == 1

      # The revoked key should be the original one
      assert hd(revoked_keys).id == first_key.id

      # Revoke the remaining active key
      active_key = hd(active_keys)

      html =
        lv
        |> element(~s(button[phx-click="revoke_key"][phx-value-key-id="#{active_key.id}"]))
        |> render_click()

      # All keys should now show as Revoked
      assert html =~ "Revoked"

      keys = Keys.list_keys(api.id)
      assert Enum.all?(keys, & &1.revoked_at)
    end
  end
end
