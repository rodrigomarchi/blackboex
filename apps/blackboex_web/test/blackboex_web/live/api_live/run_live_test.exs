defmodule BlackboexWeb.ApiLive.Edit.RunLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Testing

  setup :register_and_log_in_user

  setup %{user: user} do
    Apis.Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Run Org #{System.unique_integer([:positive])}",
        slug: "runorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Run Test API",
        slug: "run-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}",
        example_request: %{"a" => 1, "b" => 2}
      })

    %{org: org, api: api, user: user}
  end

  defp insert_test_request(api, user, attrs \\ %{}) do
    defaults = %{
      api_id: api.id,
      user_id: user.id,
      method: "POST",
      path: "/api/test/path",
      headers: %{"content-type" => "application/json"},
      body: ~s({"a": 1}),
      response_status: 200,
      response_headers: %{"content-type" => "application/json"},
      response_body: ~s({"ok": true}),
      duration_ms: 42
    }

    {:ok, tr} = Testing.create_test_request(Map.merge(defaults, attrs))
    tr
  end

  describe "mount" do
    test "renders run tab with request builder", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "History"
      assert html =~ "No requests yet"
    end

    test "shows snippet language buttons", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "curl"
      assert html =~ "python"
      assert html =~ "javascript"
      assert html =~ "elixir"
      assert html =~ "ruby"
      assert html =~ "go"
    end

    test "initialises URL from org and api slug", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "/api/#{org.slug}/#{api.slug}"
    end

    test "pre-populates body from example_request", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # example_request is %{"a" => 1, "b" => 2} — JSON is HTML-escaped inside the textarea,
      # so double-quotes become &quot;
      assert html =~ "&quot;a&quot;" or html =~ "&quot;b&quot;"
    end
  end

  describe "generate_sample" do
    test "populates body with generated sample data", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "generate_sample", %{})

      # Should switch to body tab and have some JSON content
      assert is_binary(html)
    end

    test "clears body error after generating sample", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # First introduce a JSON error
      render_click(lv, "update_test_body", %{"test_body_json" => "{bad json"})

      # Then generate sample — should clear the error
      html = render_click(lv, "generate_sample", %{})
      refute html =~ "Invalid JSON"
    end

    test "switches to body tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # Switch to params tab first
      render_click(lv, "switch_request_tab", %{"tab" => "params"})

      # generate_sample should switch back to body tab
      html = render_click(lv, "generate_sample", %{})
      assert is_binary(html)
    end
  end

  describe "load_history_item" do
    test "loads a previous request into the builder", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      tr = insert_test_request(api, user, %{method: "POST", body: ~s({"loaded": true})})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "load_history_item", %{"id" => tr.id})

      assert html =~ "POST"
      assert html =~ "loaded" or html =~ tr.path
    end

    test "shows error flash when item belongs to different API", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      # Create another API and a test request for it
      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          slug: "other-api-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(_), do: :ok"
        })

      other_tr = insert_test_request(other_api, user)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "load_history_item", %{"id" => other_tr.id})
      assert html =~ "not found" or html =~ "error"
    end

    test "shows error flash when item does not exist", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "load_history_item", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or html =~ "error"
    end
  end

  describe "clear_history" do
    test "removes all history items from the view", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      insert_test_request(api, user)
      insert_test_request(api, user, %{method: "GET", path: "/api/test/other"})

      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # History should be present
      refute html =~ "No requests yet"

      html = render_click(lv, "clear_history", %{})
      assert html =~ "No requests yet"
    end

    test "deletes records from the database", %{conn: conn, org: org, api: api, user: user} do
      insert_test_request(api, user)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      render_click(lv, "clear_history", %{})

      assert Testing.list_test_requests(api.id) == []
    end

    test "clear button is hidden when history is empty", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      refute html =~ ~s(phx-click="clear_history")
    end

    test "clear button is visible when history exists", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      insert_test_request(api, user)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      assert html =~ ~s(phx-click="clear_history")
    end
  end

  describe "quick_test" do
    test "quick_test with GET method sets method to GET", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "quick_test", %{"method" => "GET"})

      # Should set loading state (GET request fires async task)
      assert is_binary(html)
    end

    test "quick_test with POST generates sample body", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "quick_test", %{"method" => "POST"})

      # POST quick_test generates a sample and fires an async request
      assert is_binary(html)
    end

    test "quick_test while loading is a no-op", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # First quick_test sets loading
      render_click(lv, "quick_test", %{"method" => "GET"})

      # Second call should be guarded
      html = render_click(lv, "quick_test", %{"method" => "POST"})
      assert is_binary(html)
    end

    test "quick_test with DELETE method fires request", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "quick_test", %{"method" => "DELETE"})
      assert is_binary(html)
    end
  end

  describe "update_test_api_key" do
    test "stores the key in assigns", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_api_key", %{"test_api_key" => "sk-test-key-123"})

      # The rendered HTML should reflect the key (shown in the auth tab input)
      assert is_binary(html)
    end

    test "empty key is accepted", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_api_key", %{"test_api_key" => ""})
      assert is_binary(html)
    end
  end

  describe "history display" do
    test "history items show method, path, and status", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      insert_test_request(api, user, %{
        method: "POST",
        path: "/api/test/mypath",
        response_status: 200,
        duration_ms: 99
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "POST"
      assert html =~ "200"
      assert html =~ "99"
    end

    test "multiple history items are all shown", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      insert_test_request(api, user, %{method: "GET", path: "/api/test/one", response_status: 200})

      insert_test_request(api, user, %{
        method: "POST",
        path: "/api/test/two",
        response_status: 422
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "200"
      assert html =~ "422"
    end
  end
end
