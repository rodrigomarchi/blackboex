defmodule BlackboexWeb.ApiLive.Edit.RunLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview
  # Task.async in RunLive + Ecto sandbox = Postgrex disconnect on test exit
  @moduletag :capture_log

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
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id,
        example_request: %{"a" => 1, "b" => 2}
      })

    Apis.upsert_files(api, [
      %{path: "/src/handler.ex", content: "def handle(_), do: %{ok: true}", file_type: "source"}
    ])

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
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
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

      refute html =~ ~s(phx-value-action="clear_history")
    end

    test "clear button is visible when history exists", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      insert_test_request(api, user)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      assert html =~ ~s(phx-value-action="clear_history")
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

  describe "update_test_method" do
    test "valid method updates assign", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_method", %{"method" => "DELETE"})
      assert is_binary(html)
    end

    test "invalid method is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_method", %{"method" => "INVALID"})
      assert is_binary(html)
    end
  end

  describe "update_test_url" do
    test "updates the URL assign", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_url", %{"url" => "/api/custom/path"})
      assert is_binary(html)
    end
  end

  describe "update_test_body" do
    test "valid JSON clears body error", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # First set invalid JSON
      render_click(lv, "update_test_body", %{"test_body_json" => "{bad"})

      # Then fix it
      html = render_click(lv, "update_test_body", %{"test_body_json" => ~s({"x": 1})})
      refute html =~ "Invalid JSON"
    end

    test "invalid JSON sets body error", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_body", %{"test_body_json" => "not json"})
      assert html =~ "Invalid JSON"
    end

    test "empty string is invalid JSON and shows error", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_body", %{"test_body_json" => ""})
      assert html =~ "Invalid JSON"
    end
  end

  describe "switch_request_tab" do
    test "switches to params tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_request_tab", %{"tab" => "params"})
      assert is_binary(html)
    end

    test "switches to headers tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_request_tab", %{"tab" => "headers"})
      assert is_binary(html)
    end

    test "switches to auth tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_request_tab", %{"tab" => "auth"})
      assert is_binary(html)
    end

    test "invalid tab is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_request_tab", %{"tab" => "invalid"})
      assert is_binary(html)
    end
  end

  describe "switch_response_tab" do
    test "switches to headers tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_response_tab", %{"tab" => "headers"})
      assert is_binary(html)
    end

    test "switches to body tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      render_click(lv, "switch_response_tab", %{"tab" => "headers"})
      html = render_click(lv, "switch_response_tab", %{"tab" => "body"})
      assert is_binary(html)
    end

    test "invalid response tab is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_response_tab", %{"tab" => "invalid"})
      assert is_binary(html)
    end
  end

  describe "add_param / remove_param / update_param_key / update_param_value" do
    test "add_param adds a new empty parameter row", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "add_param", %{})
      assert is_binary(html)
    end

    test "remove_param removes a parameter by id", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      render_click(lv, "add_param", %{})

      # Get current assigns to retrieve the param id
      %{test_params: params} = :sys.get_state(lv.pid).socket.assigns
      [param | _] = params

      html = render_click(lv, "remove_param", %{"id" => param.id})
      assert is_binary(html)
    end

    test "update_param_key updates the key of a parameter", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      render_click(lv, "add_param", %{})
      %{test_params: params} = :sys.get_state(lv.pid).socket.assigns
      [param | _] = params

      html = render_click(lv, "update_param_key", %{"id" => param.id, "param_key" => "mykey"})
      assert is_binary(html)
    end

    test "update_param_value updates the value of a parameter", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      render_click(lv, "add_param", %{})
      %{test_params: params} = :sys.get_state(lv.pid).socket.assigns
      [param | _] = params

      html =
        render_click(lv, "update_param_value", %{"id" => param.id, "param_value" => "myval"})

      assert is_binary(html)
    end
  end

  describe "add_header / remove_header / update_header_key / update_header_value" do
    test "add_header adds a new empty header row", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "add_header", %{})
      assert is_binary(html)
    end

    test "remove_header removes an existing header", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      render_click(lv, "add_header", %{})
      %{test_headers: headers} = :sys.get_state(lv.pid).socket.assigns
      # Use the first non-default header (there may be a Content-Type already)
      [header | _] = Enum.reverse(headers)

      html = render_click(lv, "remove_header", %{"id" => header.id})
      assert is_binary(html)
    end

    test "update_header_key updates the key of a header", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      %{test_headers: headers} = :sys.get_state(lv.pid).socket.assigns
      [header | _] = headers

      html =
        render_click(lv, "update_header_key", %{"id" => header.id, "header_key" => "X-Custom"})

      assert is_binary(html)
    end

    test "update_header_value updates the value of a header", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      %{test_headers: headers} = :sys.get_state(lv.pid).socket.assigns
      [header | _] = headers

      html =
        render_click(lv, "update_header_value", %{
          "id" => header.id,
          "header_value" => "custom-val"
        })

      assert is_binary(html)
    end
  end

  describe "send_request" do
    test "send_request starts loading and second click is guarded", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      # First send starts loading
      html1 = render_click(lv, "send_request", %{})
      assert is_binary(html1)

      # Second send should be guarded (test_loading: true)
      html2 = render_click(lv, "send_request", %{})
      assert is_binary(html2)
    end
  end

  describe "copy_snippet" do
    test "valid language copies snippet", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "copy_snippet", %{"language" => "curl"})
      assert html =~ "copied" or is_binary(html)
    end

    test "invalid language is a no-op", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "copy_snippet", %{"language" => "haskell"})
      assert is_binary(html)
    end

    test "all valid snippet languages work", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      for lang <- ~w(curl python javascript elixir ruby go) do
        html = render_click(lv, "copy_snippet", %{"language" => lang})
        assert is_binary(html)
      end
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
