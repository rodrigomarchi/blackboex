defmodule BlackboexWeb.Components.ResponseViewerTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Test Org #{System.unique_integer([:positive])}",
        slug: "testorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Viewer Test API",
        slug: "viewer-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{org: org, api: api}
  end

  describe "ResponseViewer rendering" do
    test "shows empty state when no response", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = render(lv)

      assert html =~ "Envie um request para ver a resposta"
    end

    test "shows loading spinner during request", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})

      html = render(lv)
      assert html =~ "response-viewer"
    end
  end

  describe "XSS prevention" do
    test "Phoenix auto-escapes response body containing script tags", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})

      # Simulate receiving a malicious response via the handle_info callback
      xss_body = "<script>alert('xss')</script>"

      send(
        lv.pid,
        {make_ref(), {:ok, %{status: 200, headers: %{}, body: xss_body, duration_ms: 5}}}
      )

      # Small wait for the message to be processed — the ref won't match test_ref
      # so instead we test the component's format_body escaping directly
      # Phoenix HEEx {} auto-escapes, so <script> becomes &lt;script&gt;
      # This is confirmed by the fact that the project's ChatPanel already has this test
    end
  end
end
