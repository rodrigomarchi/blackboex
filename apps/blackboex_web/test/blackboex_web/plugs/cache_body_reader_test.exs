defmodule BlackboexWeb.Plugs.CacheBodyReaderTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias BlackboexWeb.Plugs.CacheBodyReader

  import Plug.Test, only: [conn: 3]

  describe "read_body/2" do
    test "caches the raw body in conn assigns" do
      body = Jason.encode!(%{"key" => "value"})
      conn = conn(:post, "/webhook", body) |> put_req_header("content-type", "application/json")
      conn = Plug.Conn.fetch_query_params(conn)

      {:ok, read_body, conn} = CacheBodyReader.read_body(conn, [])

      assert read_body == body
      assert conn.assigns[:raw_body] != nil
    end

    test "get_raw_body/1 returns the cached body as a string" do
      body = Jason.encode!(%{"event" => "charge.succeeded"})
      conn = conn(:post, "/webhook", body) |> put_req_header("content-type", "application/json")

      {:ok, _read, conn} = CacheBodyReader.read_body(conn, [])

      assert CacheBodyReader.get_raw_body(conn) == body
    end

    test "get_raw_body/1 returns empty string when no body cached" do
      conn = build_conn(:get, "/")

      assert CacheBodyReader.get_raw_body(conn) == ""
    end

    test "works with empty body" do
      conn = conn(:post, "/webhook", "")

      {:ok, read_body, conn} = CacheBodyReader.read_body(conn, [])

      assert read_body == ""
      assert CacheBodyReader.get_raw_body(conn) == ""
    end

    test "works with large body" do
      large_body = String.duplicate("a", 10_000)
      conn = conn(:post, "/webhook", large_body)

      {:ok, _read, conn} = CacheBodyReader.read_body(conn, [])

      assert CacheBodyReader.get_raw_body(conn) == large_body
    end

    test "accumulates body across multiple reads" do
      # Simulate chunked reads: raw_body is a list of chunks
      conn = build_conn(:post, "/webhook")

      # Manually set raw_body to simulate a first chunk already read
      conn = Plug.Conn.assign(conn, :raw_body, ["chunk1"])

      # Directly call update_in to simulate what read_body does on second chunk
      conn = update_in(conn.assigns[:raw_body], &["chunk2" | &1 || []])

      assert CacheBodyReader.get_raw_body(conn) == "chunk1chunk2"
    end

    test "get_raw_body/1 handles binary assign directly" do
      conn =
        build_conn(:get, "/")
        |> Plug.Conn.assign(:raw_body, "direct-binary")

      assert CacheBodyReader.get_raw_body(conn) == "direct-binary"
    end

    test "preserves body integrity for webhook signature verification" do
      # This is the primary use-case: raw body must match exactly for HMAC
      payload = ~s({"type":"payment_intent.succeeded","data":{"object":{"id":"pi_123"}}})
      conn = conn(:post, "/webhooks/stripe", payload)

      {:ok, _read, conn} = CacheBodyReader.read_body(conn, [])

      raw = CacheBodyReader.get_raw_body(conn)
      assert raw == payload
      assert byte_size(raw) == byte_size(payload)
    end
  end
end
