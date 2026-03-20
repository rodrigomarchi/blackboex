defmodule BlackboexWeb.Plugs.HealthCheckTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias BlackboexWeb.Plugs.HealthCheck

  @opts HealthCheck.init([])

  describe "GET /health/live" do
    test "returns 200 always" do
      conn =
        build_conn(:get, "/health/live")
        |> HealthCheck.call(@opts)

      assert conn.status == 200
      assert conn.halted

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
    end
  end

  describe "GET /health/ready" do
    test "returns 200 when DB is accessible" do
      conn =
        build_conn(:get, "/health/ready")
        |> HealthCheck.call(@opts)

      assert conn.status == 200
      assert conn.halted

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["checks"]["database"] == "ok"
      assert body["checks"]["registry"] == "ok"
    end
  end

  describe "GET /health/startup" do
    test "returns 200 when app has started" do
      conn =
        build_conn(:get, "/health/startup")
        |> HealthCheck.call(@opts)

      assert conn.status == 200
      assert conn.halted

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["checks"]["database"] == "ok"
    end

    test "startup check does not include registry" do
      conn =
        build_conn(:get, "/health/startup")
        |> HealthCheck.call(@opts)

      body = Jason.decode!(conn.resp_body)
      refute Map.has_key?(body["checks"], "registry")
    end
  end

  describe "non-health paths" do
    test "passes through without halting" do
      conn =
        build_conn(:get, "/api/test")
        |> HealthCheck.call(@opts)

      refute conn.halted
      assert conn.status == nil
    end

    test "passes through for partial match" do
      conn =
        build_conn(:get, "/healthy")
        |> HealthCheck.call(@opts)

      refute conn.halted
      assert conn.status == nil
    end
  end

  describe "response format" do
    test "returns JSON content type" do
      conn =
        build_conn(:get, "/health/live")
        |> HealthCheck.call(@opts)

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end
end
