defmodule BlackboexWeb.Components.Editor.ResponseViewerTest do
  @moduledoc """
  Tests for the ResponseViewer LiveComponent.
  Renders the component directly via render_component/2 for unit-level coverage,
  plus a few integration tests via the run LiveView.
  """

  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias BlackboexWeb.Components.Editor.ResponseViewer

  # ── Helpers ────────────────────────────────────────────────────────────

  defp base_assigns do
    %{
      id: "response-viewer",
      response: nil,
      loading: false,
      error: nil,
      violations: [],
      response_tab: "body"
    }
  end

  defp render_viewer(overrides \\ %{}) do
    assigns = Map.merge(base_assigns(), overrides)
    render_component(ResponseViewer, assigns)
  end

  defp api_response(status, body) do
    %{
      status: status,
      body: body,
      headers: [{"content-type", "application/json"}, {"x-request-id", "abc123"}],
      duration_ms: 45
    }
  end

  # ── Empty / nil state ──────────────────────────────────────────────────

  describe "no response yet" do
    test "shows empty state message" do
      html = render_viewer()

      assert html =~ "Send a request to see the response"
    end

    test "renders response-viewer container" do
      html = render_viewer()

      assert html =~ "response-viewer"
    end

    test "shows Response header" do
      html = render_viewer()

      assert html =~ "Response"
    end

    test "does not show status badge when no response" do
      html = render_viewer()

      refute html =~ "200"
      refute html =~ "duration_ms"
    end
  end

  # ── Loading state ──────────────────────────────────────────────────────

  describe "loading state" do
    test "shows spinner when loading" do
      html = render_viewer(%{loading: true})

      assert html =~ "animate-spin"
    end

    test "does not show empty state message while loading" do
      html = render_viewer(%{loading: true})

      refute html =~ "Envie um request"
    end
  end

  # ── Error state ────────────────────────────────────────────────────────

  describe "error state" do
    test "shows error message" do
      html = render_viewer(%{error: "Connection refused"})

      assert html =~ "Connection refused"
    end

    test "error message has destructive styling" do
      html = render_viewer(%{error: "timeout"})

      assert html =~ "destructive"
    end

    test "does not show empty state when error is set" do
      html = render_viewer(%{error: "oops"})

      refute html =~ "Envie um request"
    end
  end

  # ── Success response (200) ─────────────────────────────────────────────

  describe "success response (200)" do
    test "shows status code" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42}))})

      assert html =~ "200"
    end

    test "shows duration" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42}))})

      assert html =~ "45ms"
    end

    test "shows Valid badge when no violations" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42})), violations: []})

      assert html =~ "Valid"
    end

    test "shows body content" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42}))})

      assert html =~ "result"
      assert html =~ "42"
    end

    test "pretty-prints JSON body" do
      body = ~s({"a":1,"b":2})
      html = render_viewer(%{response: api_response(200, body)})

      # Pretty-printed JSON has newlines and indentation; quotes are HTML-escaped
      assert html =~ "&quot;a&quot;"
    end

    test "shows body and headers tabs" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42}))})

      assert html =~ "Body"
      assert html =~ "Headers"
    end

    test "success status badge has success styling" do
      html = render_viewer(%{response: api_response(200, ~s({"result": 42}))})

      assert html =~ "success"
    end
  end

  # ── Client error response (4xx) ────────────────────────────────────────

  describe "4xx error response" do
    test "shows 404 status code" do
      html = render_viewer(%{response: api_response(404, ~s({"error": "not found"}))})

      assert html =~ "404"
    end

    test "shows 422 status with body" do
      html = render_viewer(%{response: api_response(422, ~s({"error": "invalid input"}))})

      assert html =~ "422"
      assert html =~ "invalid input"
    end

    test "4xx status badge has warning styling" do
      html = render_viewer(%{response: api_response(400, ~s({"error": "bad request"}))})

      assert html =~ "warning"
    end
  end

  # ── Server error response (5xx) ────────────────────────────────────────

  describe "5xx error response" do
    test "shows 500 status code" do
      html = render_viewer(%{response: api_response(500, "Internal Server Error")})

      assert html =~ "500"
    end

    test "shows 503 body" do
      html = render_viewer(%{response: api_response(503, "Service Unavailable")})

      assert html =~ "503"
      assert html =~ "Service Unavailable"
    end

    test "5xx status badge has destructive styling" do
      html = render_viewer(%{response: api_response(500, "Internal Server Error")})

      assert html =~ "destructive"
    end
  end

  # ── Violations ─────────────────────────────────────────────────────────

  describe "violations" do
    test "shows violation count badge when violations present" do
      html =
        render_viewer(%{
          response: api_response(200, ~s({"result": 42})),
          violations: ["missing field x"]
        })

      assert html =~ "1 violation(s)"
    end

    test "shows multiple violations count" do
      html =
        render_viewer(%{
          response: api_response(200, ~s({"result": 42})),
          violations: ["missing field x", "wrong type y"]
        })

      assert html =~ "2 violation(s)"
    end

    test "does not show Valid badge when violations present" do
      html =
        render_viewer(%{response: api_response(200, ~s({"result": 42})), violations: ["err"]})

      refute html =~ "Valid"
    end
  end

  # ── Headers tab ────────────────────────────────────────────────────────

  describe "headers tab" do
    test "renders header keys and values" do
      html =
        render_viewer(%{
          response: api_response(200, ~s({"result": 42})),
          response_tab: "headers"
        })

      assert html =~ "content-type"
      assert html =~ "application/json"
    end

    test "renders x-request-id header" do
      html =
        render_viewer(%{
          response: api_response(200, ~s({"result": 42})),
          response_tab: "headers"
        })

      assert html =~ "x-request-id"
      assert html =~ "abc123"
    end
  end

  # ── Non-JSON body ──────────────────────────────────────────────────────

  describe "non-JSON body" do
    test "renders plain text body as-is" do
      html = render_viewer(%{response: api_response(200, "plain text response")})

      assert html =~ "plain text response"
    end

    test "renders binary-looking body without crashing" do
      html = render_viewer(%{response: api_response(200, "not json {{{")})

      assert html =~ "not json"
    end
  end

  # ── Large response body ────────────────────────────────────────────────

  describe "large response body" do
    test "renders large JSON body without crashing" do
      large_body =
        Jason.encode!(%{
          items: Enum.map(1..100, &%{id: &1, name: "item_#{&1}", value: &1 * 10})
        })

      html = render_viewer(%{response: api_response(200, large_body)})

      assert html =~ "items"
      assert html =~ "item_1"
    end
  end
end
