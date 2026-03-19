defmodule Blackboex.Testing.RequestExecutorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.RequestExecutor

  defmodule OkPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts
    def call(conn, _opts), do: send_resp(conn, 200, "ok")
  end

  describe "execute/2 SSRF protection" do
    test "rejects external URLs" do
      request = %{method: :get, url: "https://evil.com/api/foo/bar", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects non-API paths" do
      request = %{method: :get, url: "/admin/dashboard", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects root path" do
      request = %{method: :get, url: "/", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects /api without username/slug" do
      request = %{method: :get, url: "/api", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects /api with only username" do
      request = %{method: :get, url: "/api/username", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "allows /api/username/slug" do
      request = %{method: :get, url: "/api/testuser/my-api", headers: [], body: nil}
      assert {:ok, _response} = RequestExecutor.execute(request, plug: OkPlug)
    end

    test "allows /api/username/slug/subpath" do
      request = %{method: :get, url: "/api/testuser/my-api/items/123", headers: [], body: nil}
      assert {:ok, _response} = RequestExecutor.execute(request, plug: OkPlug)
    end

    test "rejects protocol-relative URLs" do
      request = %{method: :get, url: "//evil.com/api/foo/bar", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects http scheme URLs" do
      request = %{method: :get, url: "http://evil.com/api/foo/bar", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "rejects ftp scheme URLs" do
      request = %{method: :get, url: "ftp://evil.com/api/foo/bar", headers: [], body: nil}
      assert {:error, :forbidden} = RequestExecutor.execute(request)
    end

    test "handles URL with query string" do
      request = %{method: :get, url: "/api/testuser/my-api?key=val", headers: [], body: nil}
      assert {:ok, _response} = RequestExecutor.execute(request, plug: OkPlug)
    end
  end

  describe "execute/2 with plug adapter" do
    defmodule TestPlug do
      @moduledoc false
      import Plug.Conn

      def init(opts), do: opts

      def call(conn, _opts) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        response =
          Jason.encode!(%{
            received_method: conn.method,
            received_path: conn.request_path,
            received_body: body
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, response)
      end
    end

    test "successful GET request returns response map" do
      request = %{method: :get, url: "/api/testuser/myapi", headers: [], body: nil}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)

      assert response.status == 200
      assert is_binary(response.body)
      assert is_integer(response.duration_ms)
      assert response.duration_ms >= 0
      assert is_map(response.headers)
    end

    test "successful POST request passes body" do
      body = Jason.encode!(%{n: 5})

      request = %{
        method: :post,
        url: "/api/testuser/myapi",
        headers: [{"content-type", "application/json"}],
        body: body
      }

      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      assert response.status == 200

      decoded = Jason.decode!(response.body)
      assert decoded["received_method"] == "POST"
      assert decoded["received_body"] == body
    end

    test "passes custom headers" do
      request = %{
        method: :get,
        url: "/api/testuser/myapi",
        headers: [{"x-api-key", "secret123"}],
        body: nil
      }

      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      assert response.status == 200
    end

    test "measures duration_ms" do
      request = %{method: :get, url: "/api/testuser/myapi", headers: [], body: nil}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      assert is_integer(response.duration_ms)
      assert response.duration_ms >= 0
    end

    test "returns headers as map" do
      request = %{method: :get, url: "/api/testuser/myapi", headers: [], body: nil}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      assert is_map(response.headers)
      assert Map.has_key?(response.headers, "content-type")
    end

    test "supports PUT method" do
      request = %{method: :put, url: "/api/testuser/myapi", headers: [], body: "{}"}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      decoded = Jason.decode!(response.body)
      assert decoded["received_method"] == "PUT"
    end

    test "supports PATCH method" do
      request = %{method: :patch, url: "/api/testuser/myapi", headers: [], body: "{}"}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      decoded = Jason.decode!(response.body)
      assert decoded["received_method"] == "PATCH"
    end

    test "supports DELETE method" do
      request = %{method: :delete, url: "/api/testuser/myapi", headers: [], body: nil}
      assert {:ok, response} = RequestExecutor.execute(request, plug: TestPlug)
      decoded = Jason.decode!(response.body)
      assert decoded["received_method"] == "DELETE"
    end
  end

  describe "execute/2 error handling" do
    test "returns connection_error for unreachable host" do
      request = %{method: :get, url: "/api/testuser/myapi", headers: [], body: nil}

      # Connect to a port that is almost certainly not listening
      assert {:error, :connection_error} =
               RequestExecutor.execute(request, base_url: "http://127.0.0.1:19999")
    end
  end
end
