defmodule BlackboexWeb.SetupControllerTest do
  use BlackboexWeb.ConnCase, async: false

  alias Blackboex.Repo
  alias Blackboex.Settings
  alias BlackboexWeb.SetupTokens

  setup do
    # /setup/finish is gated by RequireSetup once setup_completed? is true.
    # ConnCase pre-populates the cache to true; invalidate so the route is reachable.
    Settings.invalidate_cache()
    on_exit(fn -> Settings.invalidate_cache() end)
    :ok
  end

  describe "GET /setup/finish" do
    test "with valid token logs user in and redirects to signed_in_path", %{conn: conn} do
      user = user_fixture()
      token = SetupTokens.issue(user.id)

      conn = get(conn, ~p"/setup/finish?token=#{token}")

      assert redirected_to(conn) =~ ~r{^/}
      assert get_session(conn, :user_token)
    end

    test "rejects expired token", %{conn: conn} do
      user = user_fixture()
      previous_ttl = Application.get_env(:blackboex_web, :setup_token_ttl_seconds)
      Application.put_env(:blackboex_web, :setup_token_ttl_seconds, -1)

      token =
        try do
          SetupTokens.issue(user.id)
        after
          if is_nil(previous_ttl) do
            Application.delete_env(:blackboex_web, :setup_token_ttl_seconds)
          else
            Application.put_env(:blackboex_web, :setup_token_ttl_seconds, previous_ttl)
          end
        end

      conn = get(conn, ~p"/setup/finish?token=#{token}")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "rejects already-consumed token", %{conn: conn} do
      user = user_fixture()
      token = SetupTokens.issue(user.id)

      _first = get(conn, ~p"/setup/finish?token=#{token}")
      conn2 = get(build_conn(), ~p"/setup/finish?token=#{token}")

      assert redirected_to(conn2) == ~p"/users/log-in"
      refute get_session(conn2, :user_token)
    end

    test "rejects unknown token", %{conn: conn} do
      conn = get(conn, ~p"/setup/finish?token=does-not-exist")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "rejects token whose user no longer exists", %{conn: conn} do
      user = user_fixture()
      token = SetupTokens.issue(user.id)
      Repo.delete!(user)

      conn = get(conn, ~p"/setup/finish?token=#{token}")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "redirects to /users/log-in when token param is missing", %{conn: conn} do
      conn = get(conn, ~p"/setup/finish")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
