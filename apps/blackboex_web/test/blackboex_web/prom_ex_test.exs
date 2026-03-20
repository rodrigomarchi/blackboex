defmodule BlackboexWeb.PromExTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration

  describe "GET /metrics" do
    test "returns 200 with Prometheus text format" do
      conn = build_conn(:get, "/metrics")
      conn = BlackboexWeb.Endpoint.call(conn, [])

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
      assert conn.resp_body =~ "beam_"
    end
  end
end
