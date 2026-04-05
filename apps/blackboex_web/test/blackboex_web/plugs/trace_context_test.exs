defmodule BlackboexWeb.Plugs.TraceContextTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias BlackboexWeb.Plugs.TraceContext

  describe "call/2" do
    test "passes through conn unchanged when no active span" do
      conn = build_conn(:get, "/")

      result = TraceContext.call(conn, [])

      assert result == conn
    end

    test "returns a conn (does not raise) regardless of OTel state" do
      conn = build_conn(:get, "/some/path")

      # Should not raise even if OpenTelemetry is not configured
      assert %Plug.Conn{} = TraceContext.call(conn, [])
    end

    test "init/1 returns opts as-is" do
      opts = [some: :option]
      assert TraceContext.init(opts) == opts
    end

    test "init/1 works with empty opts" do
      assert TraceContext.init([]) == []
    end

    test "does not halt the conn" do
      conn = build_conn(:get, "/")

      result = TraceContext.call(conn, [])

      refute result.halted
    end

    test "does not modify the conn when no trace context is available" do
      conn = build_conn(:get, "/api/test")

      result = TraceContext.call(conn, [])

      assert result.method == conn.method
      assert result.request_path == conn.request_path
      assert result.status == conn.status
    end

    test "works with POST requests" do
      conn = build_conn(:post, "/api/test")

      assert %Plug.Conn{} = TraceContext.call(conn, [])
    end

    test "works across multiple calls (stateless)" do
      conn1 = build_conn(:get, "/path1")
      conn2 = build_conn(:get, "/path2")

      result1 = TraceContext.call(conn1, [])
      result2 = TraceContext.call(conn2, [])

      assert result1.request_path == "/path1"
      assert result2.request_path == "/path2"
    end
  end
end
