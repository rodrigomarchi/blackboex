defmodule BlackboexWeb.Components.RequestBuilderTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Testing

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Test Org #{System.unique_integer([:positive])}",
        slug: "testorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Builder Test API",
        slug: "builder-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{org: org, api: api, user: user}
  end

  describe "RequestBuilder rendering" do
    test "renders method selector with all HTTP methods", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = render(lv)

      assert html =~ "GET"
      assert html =~ "POST"
      assert html =~ "PUT"
      assert html =~ "PATCH"
      assert html =~ "DELETE"
    end

    test "renders URL field pre-filled with API path", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = render(lv)

      assert html =~ "/api/#{org.slug}/#{api.slug}"
    end

    test "renders sub-tabs for Params, Headers, Body, Auth", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = render(lv)

      assert html =~ "Params"
      assert html =~ "Headers"
      assert html =~ "Body"
      assert html =~ "Auth"
    end

    test "renders Send button", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = render(lv)

      assert html =~ "Enviar"
    end
  end

  describe "history authorization" do
    test "load_history_item rejects requests from other APIs", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      # Create a second API
      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          slug: "other-api-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      # Create a test request for the OTHER api
      {:ok, other_request} =
        Testing.create_test_request(%{
          api_id: other_api.id,
          user_id: user.id,
          method: "GET",
          path: "/api/org/other",
          response_status: 200,
          response_body: "secret data",
          duration_ms: 10
        })

      # Open edit page for the FIRST api
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})

      # Try to load history item from the OTHER api — should be rejected
      html = render_click(lv, "load_history_item", %{"id" => other_request.id})
      # Flash is rendered by app layout; verify the other API's data is NOT loaded
      refute html =~ "secret data"
    end
  end

  describe "input validation" do
    test "ignores invalid method values", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})

      # Send an invalid method — should be ignored
      render_click(lv, "update_test_method", %{"method" => "INVALID"})
      html = render(lv)
      # Method should still be the default, not "INVALID"
      refute html =~ "INVALID"
    end

    test "ignores invalid snippet language", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> render_click("switch_tab", %{"tab" => "run"})

      # Should not crash
      render_click(lv, "copy_snippet", %{"language" => "php"})
      html = render(lv)
      assert html =~ "Enviar"
    end
  end
end
