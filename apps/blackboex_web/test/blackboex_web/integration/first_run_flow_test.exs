defmodule BlackboexWeb.Integration.FirstRunFlowTest do
  use BlackboexWeb.ConnCase, async: false

  alias Blackboex.Settings

  setup do
    # Force a "fresh install" state for this test only.
    Settings.invalidate_cache()
    on_exit(fn -> Settings.invalidate_cache() end)
    :ok
  end

  describe "fresh install (no instance_settings row)" do
    setup do
      :persistent_term.put({Blackboex.Settings, :setup_completed?}, false)
      :ok
    end

    test "GET / redirects to /setup", %{conn: conn} do
      conn = get(conn, "/")
      assert redirected_to(conn) == "/setup"
    end

    test "GET /users/log-in redirects to /setup", %{conn: conn} do
      conn = get(conn, "/users/log-in")
      assert redirected_to(conn) == "/setup"
    end

    test "API endpoints continue to respond (no redirect to /setup)", %{conn: conn} do
      conn = get(conn, "/api/this-route-does-not-exist-but-is-not-redirected")
      # Status may be 404 (no matching API) or another non-redirect status,
      # but the response MUST NOT be a redirect to /setup.
      refute conn.status in [301, 302, 303, 307, 308] and
               get_resp_header(conn, "location") == ["/setup"]
    end

    test "/setup itself is reachable (200)", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/setup")
      assert html =~ "First-run setup"
    end
  end

  describe "completed install" do
    setup do
      instance_setting_fixture()
      :ok
    end

    test "GET /setup returns 404", %{conn: conn} do
      conn = get(conn, "/setup")
      assert conn.status == 404
    end

    test "GET /users/register returns 404 (route deleted)", %{conn: conn} do
      conn = get(conn, "/users/register")
      assert conn.status == 404
    end
  end
end
