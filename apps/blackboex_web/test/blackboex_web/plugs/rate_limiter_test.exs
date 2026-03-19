defmodule BlackboexWeb.Plugs.RateLimiterTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :unit

  alias BlackboexWeb.Plugs.RateLimiter

  describe "check_rate/2" do
    test "allows requests within IP limit" do
      conn = build_conn(:get, "/api/org/test")
      metadata = %{api_id: Ecto.UUID.generate(), requires_auth: false, visibility: "public"}

      assert {:ok, conn} = RateLimiter.check_rate(conn, metadata)
      assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]

      remaining = get_resp_header(conn, "x-ratelimit-remaining")
      assert length(remaining) == 1
    end

    test "denies requests beyond IP limit" do
      metadata = %{api_id: Ecto.UUID.generate(), requires_auth: false, visibility: "public"}
      ip = {10, 0, 0, unique_integer()}

      # Exhaust the limit
      for _ <- 1..100 do
        conn = %{build_conn(:get, "/api/org/test") | remote_ip: ip}
        assert {:ok, _conn} = RateLimiter.check_rate(conn, metadata)
      end

      # Next request should be denied
      conn = %{build_conn(:get, "/api/org/test") | remote_ip: ip}
      assert {:error, :rate_limited, retry_after} = RateLimiter.check_rate(conn, metadata)
      assert is_integer(retry_after)
      assert retry_after >= 0
    end

    test "applies per-API-key limit when api_key is assigned" do
      api_key_id = Ecto.UUID.generate()
      api_key = %{id: api_key_id, rate_limit: 2}

      metadata = %{api_id: Ecto.UUID.generate(), requires_auth: true, visibility: "private"}

      # Use unique IP to avoid IP rate limit collision
      ip = {10, 1, 0, unique_integer()}

      # First 2 should pass
      for _ <- 1..2 do
        conn =
          %{build_conn(:get, "/api/org/test") | remote_ip: ip}
          |> Plug.Conn.assign(:api_key, api_key)

        assert {:ok, _conn} = RateLimiter.check_rate(conn, metadata)
      end

      # Third should be denied
      conn =
        %{build_conn(:get, "/api/org/test") | remote_ip: ip}
        |> Plug.Conn.assign(:api_key, api_key)

      assert {:error, :rate_limited, _retry} = RateLimiter.check_rate(conn, metadata)
    end

    test "skips api_key limit when no key assigned" do
      conn = build_conn(:get, "/api/org/test")
      metadata = %{api_id: Ecto.UUID.generate(), requires_auth: false, visibility: "public"}

      assert {:ok, _conn} = RateLimiter.check_rate(conn, metadata)
    end
  end

  defp unique_integer, do: System.unique_integer([:positive]) |> rem(254) |> Kernel.+(1)
end
