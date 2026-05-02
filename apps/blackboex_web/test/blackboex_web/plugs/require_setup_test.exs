defmodule BlackboexWeb.Plugs.RequireSetupTest do
  use BlackboexWeb.ConnCase, async: false

  alias Blackboex.Settings
  alias BlackboexWeb.Plugs.RequireSetup

  setup do
    Settings.invalidate_cache()
    on_exit(fn -> Settings.invalidate_cache() end)
    :ok
  end

  describe "call/2 when setup is NOT completed" do
    for path <- ["/", "/users/register", "/users/log-in", "/admin", "/orgs/foo/projects/bar"] do
      test "redirects #{path} when setup not completed", %{conn: conn} do
        conn = %{conn | request_path: unquote(path), method: "GET"}
        conn = RequireSetup.call(conn, RequireSetup.init([]))
        assert conn.halted
        assert redirected_to(conn) == "/setup"
      end
    end

    for path <- [
          "/setup",
          "/setup/finish",
          "/api/v1/foo",
          "/p/org/api",
          "/webhook/abc",
          "/assets/app.js",
          "/dev/dashboard"
        ] do
      test "passes through #{path} when setup not completed", %{conn: conn} do
        conn = %{conn | request_path: unquote(path), method: "GET"}
        result = RequireSetup.call(conn, RequireSetup.init([]))
        refute result.halted
      end
    end

    test "redirects GET / via full router pipeline", %{conn: conn} do
      conn = get(conn, "/")
      assert redirected_to(conn) == "/setup"
    end
  end

  describe "call/2 when setup IS completed" do
    setup do
      Blackboex.InstanceSettingsFixtures.instance_setting_fixture()
      :ok
    end

    test "passes through /", %{conn: conn} do
      conn = %{conn | request_path: "/", method: "GET"}
      result = RequireSetup.call(conn, RequireSetup.init([]))
      refute result.halted
    end

    test "returns 404 on GET /setup", %{conn: conn} do
      conn = %{conn | request_path: "/setup", method: "GET"}
      result = RequireSetup.call(conn, RequireSetup.init([]))
      assert result.halted
      assert result.status == 404
    end

    test "passes through GET /setup/finish so the controller hop can log the new admin in",
         %{conn: conn} do
      # Post-completion, /setup/finish must remain reachable: SetupLive
      # redirects to it with a one-time SetupTokens token after the wizard's
      # transaction commits. The token's TTL + single-use semantics guard it,
      # not URL gating.
      conn = %{conn | request_path: "/setup/finish", method: "GET"}
      result = RequireSetup.call(conn, RequireSetup.init([]))
      refute result.halted
    end
  end
end
