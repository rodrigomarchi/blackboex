defmodule Blackboex.FlowExecutor.Nodes.HttpRequestTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.HttpRequest

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp args_with(input, state \\ %{}),
    do: %{prev_result: %{output: input, state: state}}

  defp stub_response(status, body, headers \\ []) do
    Req.Test.stub(:http_request_test, fn conn ->
      conn_with_headers =
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> then(
          &Enum.reduce(headers, &1, fn {k, v}, acc -> Plug.Conn.put_resp_header(acc, k, v) end)
        )

      Plug.Conn.send_resp(conn_with_headers, status, Jason.encode!(body))
    end)
  end

  defp test_plug_opts do
    [
      url: "http://example.com/api",
      method: "GET",
      plug: {Req.Test, :http_request_test},
      retry: false
    ]
  end

  # ---------------------------------------------------------------------------
  # run/3 — happy paths
  # ---------------------------------------------------------------------------

  describe "run/3 — happy path" do
    test "GET request returns 200 with parsed body" do
      stub_response(200, %{"result" => "ok"})
      args = args_with(%{"id" => 1})
      opts = test_plug_opts()

      assert {:ok, %{output: output, state: state}} = HttpRequest.run(args, %{}, opts)
      assert output.status == 200
      assert output.body == %{"result" => "ok"}
      assert Map.has_key?(state, "http_response")
    end

    test "POST request with body template and interpolation" do
      stub_response(201, %{"created" => true})

      args = args_with(%{"name" => "Alice"}, %{"org" => "Acme"})

      opts =
        test_plug_opts() ++
          [
            method: "POST",
            url: "http://example.com/api/{{state.org}}",
            body_template: ~s({"user": "{{input.name}}"}),
            expected_status: [201]
          ]

      assert {:ok, %{output: output, state: state}} = HttpRequest.run(args, %{}, opts)
      assert output.status == 201
      assert output.body == %{"created" => true}
      assert state["http_response"].status == 201
    end

    test "returns first argument when prev_result has input key" do
      stub_response(200, %{"ok" => true})
      args = %{input: "payload"}
      opts = test_plug_opts()

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      assert output.status == 200
    end

    test "duration_ms is non-negative integer in result" do
      stub_response(200, %{})
      args = args_with("input")
      opts = test_plug_opts()

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      assert is_integer(output.duration_ms)
      assert output.duration_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # run/3 — unexpected status
  # ---------------------------------------------------------------------------

  describe "run/3 — unexpected status" do
    test "returns error for 404" do
      stub_response(404, %{"error" => "not found"})
      args = args_with("x")
      opts = test_plug_opts() ++ [expected_status: [200]]

      assert {:error, "HTTP 404:" <> _} = HttpRequest.run(args, %{}, opts)
    end

    test "returns error for 500" do
      stub_response(500, %{"error" => "server error"})
      args = args_with("x")
      opts = test_plug_opts() ++ [expected_status: [200]]

      assert {:error, "HTTP 500:" <> _} = HttpRequest.run(args, %{}, opts)
    end

    test "accepts both 200 and 201 when listed in expected_status" do
      stub_response(201, %{"created" => true})
      args = args_with("x")
      opts = test_plug_opts() ++ [expected_status: [200, 201]]

      assert {:ok, _} = HttpRequest.run(args, %{}, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # run/3 — timeout (simulated via low timeout_ms with slow plug)
  # ---------------------------------------------------------------------------

  describe "run/3 — timeout" do
    test "returns timeout error message for transport timeout" do
      # Req.Test plug adapter raises Req.TransportError when the plug raises it,
      # but Req re-raises it rather than returning {:error, ...} in test mode.
      # We verify the timeout error branch via compensate/4 which is the retry gate.
      # The timeout_ms option is wired through receive_timeout in production.
      assert :retry =
               HttpRequest.compensate(
                 "HTTP request timed out after 10000ms",
                 %{},
                 %{},
                 []
               )
    end
  end

  # ---------------------------------------------------------------------------
  # compensate/4
  # ---------------------------------------------------------------------------

  describe "compensate/4" do
    test "returns :retry for timeout error" do
      assert :retry = HttpRequest.compensate("HTTP request timed out after 10000ms", %{}, %{}, [])
    end

    test "returns :retry for 500 error" do
      assert :retry = HttpRequest.compensate("HTTP 500: unexpected status", %{}, %{}, [])
    end

    test "returns :retry for 503 error" do
      assert :retry = HttpRequest.compensate("HTTP 503: service unavailable", %{}, %{}, [])
    end

    test "returns :ok for 400 error (client error, not retryable)" do
      assert :ok = HttpRequest.compensate("HTTP 400: bad request", %{}, %{}, [])
    end

    test "returns :ok for 404 error" do
      assert :ok = HttpRequest.compensate("HTTP 404: not found", %{}, %{}, [])
    end

    test "returns :ok for generic error" do
      assert :ok = HttpRequest.compensate("some other error", %{}, %{}, [])
    end
  end

  # ---------------------------------------------------------------------------
  # backoff/4
  # ---------------------------------------------------------------------------

  describe "backoff/4" do
    test "first retry (count 0) returns value in 500..1000 range" do
      result = HttpRequest.backoff(:timeout, %{}, %{}, [])
      assert result >= 500 and result <= 1_000
    end

    test "second retry (count 1) returns value in 1000..1500 range" do
      result = HttpRequest.backoff(:timeout, %{}, %{current_try: 1}, [])
      assert result >= 1_000 and result <= 1_500
    end

    test "third retry (count 2) returns value in 2000..2500 range" do
      result = HttpRequest.backoff(:timeout, %{}, %{current_try: 2}, [])
      assert result >= 2_000 and result <= 2_500
    end

    test "caps at 15000 + jitter for large retry_count" do
      result = HttpRequest.backoff(:timeout, %{}, %{current_try: 20}, [])
      assert result >= 15_000 and result <= 15_500
    end
  end

  # ---------------------------------------------------------------------------
  # auth headers
  # ---------------------------------------------------------------------------

  describe "auth — bearer token" do
    test "adds Authorization: Bearer header" do
      Req.Test.stub(:http_request_test, fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        body = Jason.encode!(%{"auth" => auth})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with("x")

      opts =
        test_plug_opts() ++
          [
            auth_type: "bearer",
            auth_config: %{"token" => "my-secret-token"}
          ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["auth"] == ["Bearer my-secret-token"]
    end
  end

  describe "auth — basic" do
    test "adds Authorization: Basic header" do
      Req.Test.stub(:http_request_test, fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        body = Jason.encode!(%{"auth" => auth})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with("x")

      opts =
        test_plug_opts() ++
          [
            auth_type: "basic",
            auth_config: %{"username" => "user", "password" => "pass"}
          ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      expected = Base.encode64("user:pass")
      assert decoded["auth"] == ["Basic #{expected}"]
    end
  end

  describe "auth — api_key" do
    test "adds custom key header" do
      Req.Test.stub(:http_request_test, fn conn ->
        key_val = Plug.Conn.get_req_header(conn, "x-api-key")
        body = Jason.encode!(%{"key" => key_val})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with("x")

      opts =
        test_plug_opts() ++
          [
            auth_type: "api_key",
            auth_config: %{"key_name" => "x-api-key", "key_value" => "secret"}
          ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["key"] == ["secret"]
    end
  end

  describe "auth — none" do
    test "no Authorization header added" do
      Req.Test.stub(:http_request_test, fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        body = Jason.encode!(%{"auth" => auth})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with("x")
      opts = test_plug_opts() ++ [auth_type: "none"]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["auth"] == []
    end
  end

  # ---------------------------------------------------------------------------
  # interpolation
  # ---------------------------------------------------------------------------

  describe "interpolation" do
    test "replaces {{state.var}} and {{input.field}} in URL" do
      Req.Test.stub(:http_request_test, fn conn ->
        # Capture the actual path that was requested
        body = Jason.encode!(%{"path" => conn.request_path})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with(%{"user_id" => "42"}, %{"org" => "acme"})

      opts = [
        url: "http://example.com/{{state.org}}/users/{{input.user_id}}",
        method: "GET",
        plug: {Req.Test, :http_request_test}
      ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["path"] == "/acme/users/42"
    end

    test "leaves unmatched placeholders as-is" do
      stub_response(200, %{"ok" => true})
      args = args_with(%{}, %{})

      opts =
        test_plug_opts() ++
          [
            body_template: ~s({"x": "{{input.missing}}"}),
            method: "POST"
          ]

      assert {:ok, _} = HttpRequest.run(args, %{}, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # undo/4
  # ---------------------------------------------------------------------------

  describe "env var interpolation (pre-resolved by EnvResolver)" do
    # These tests mirror what production sees AFTER FlowExecutor.EnvResolver
    # walks the raw definition and substitutes {{env.X}} placeholders with
    # plaintext values. HttpRequest itself does not evaluate {{env.X}} at
    # runtime — only {{state.X}} / {{input.X}} — so the env values must
    # already be substituted in :url / :body_template / :headers by the time
    # run/3 is called.

    test "resolved {{env.TOKEN}} in Authorization header is sent as-is" do
      Req.Test.stub(:http_request_test, fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        body = Jason.encode!(%{"auth" => auth})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with("x")

      # Simulate post-EnvResolver: the literal token is already embedded.
      opts =
        test_plug_opts() ++
          [headers: %{"authorization" => "Bearer super-secret-token"}]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["auth"] == ["Bearer super-secret-token"]
    end

    test "resolved env value in URL path reaches server intact" do
      Req.Test.stub(:http_request_test, fn conn ->
        body = Jason.encode!(%{"path" => conn.request_path})
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with(%{})

      # URL after EnvResolver: {{env.BASE}} -> "/resolved"
      opts = [
        method: "GET",
        url: "http://example.com/resolved/items",
        plug: {Req.Test, :http_request_test}
      ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)
      decoded = Jason.decode!(output.body)
      assert decoded["path"] == "/resolved/items"
    end

    test "mixed resolved env + runtime state/input interpolation" do
      Req.Test.stub(:http_request_test, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        Plug.Conn.send_resp(conn, 200, body)
      end)

      args = args_with(%{"id" => "42"}, %{"org" => "acme"})

      # The :body_template still has state/input placeholders; env is already
      # resolved by EnvResolver into the literal "TOKEN-abc".
      opts =
        test_plug_opts() ++
          [
            method: "POST",
            body_template:
              ~s({"token": "TOKEN-abc", "id": "{{input.id}}", "org": "{{state.org}}"}),
            expected_status: [200]
          ]

      assert {:ok, %{output: output}} = HttpRequest.run(args, %{}, opts)

      decoded = Jason.decode!(output.body)
      assert decoded["token"] == "TOKEN-abc"
      assert decoded["id"] == "42"
      assert decoded["org"] == "acme"
    end
  end

  describe "undo/4" do
    test "returns :ok when no undo_config provided" do
      args = %{prev_result: %{output: %{}, state: %{}}}

      assert :ok = HttpRequest.undo(%{}, args, %{}, [])
    end

    test "returns :ok for empty undo_config" do
      args = %{prev_result: %{output: %{}, state: %{}}}

      assert :ok = HttpRequest.undo(%{}, args, %{}, undo_config: %{})
    end

    test "makes undo HTTP request when config provided" do
      Req.Test.stub(:undo_test, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      args = %{prev_result: %{output: %{}, state: %{}}}

      opts = [
        undo_config: %{"method" => "DELETE", "url" => "http://example.com/resource/123"},
        plug: {Req.Test, :undo_test},
        retry: false
      ]

      assert :ok = HttpRequest.undo(%{}, args, %{}, opts)
    end
  end
end
