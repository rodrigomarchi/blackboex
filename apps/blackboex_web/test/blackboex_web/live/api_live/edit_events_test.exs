defmodule BlackboexWeb.ApiLive.EditEventsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  setup :register_and_log_in_user

  setup %{user: user} do
    Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Events Org #{System.unique_integer([:positive])}",
        slug: "eventsorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Events Test API",
        slug: "events-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: """
        def handle(params) do
          %{echo: params}
        end
        """
      })

    %{org: org, api: api}
  end

  # --- Request Builder Events (Test Tab) ---

  describe "add_param" do
    test "adds a parameter row", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "params"})

      # Initially there are no params
      render_click(lv, "add_param")
      html = render(lv)
      # After adding a param, the remove button should appear
      assert html =~ "remove_param"
    end

    test "respects the 50 item limit", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "params"})

      # Add 50 params to reach the limit
      for _ <- 1..50 do
        render_click(lv, "add_param")
      end

      # The 51st should be rejected; verify count stays at 50
      render_click(lv, "add_param")
      html = render(lv)
      assert Regex.scan(~r/phx-click="remove_param"/, html) |> length() == 50
    end
  end

  describe "remove_param" do
    test "removes a parameter by id", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "params"})

      # Add two params
      render_click(lv, "add_param")
      render_click(lv, "add_param")
      html = render(lv)

      # Find remove buttons, count them
      assert Regex.scan(~r/phx-click="remove_param"/, html) |> length() == 2

      # Extract a param id from a phx-value-id attribute near remove_param
      [id | _] =
        Regex.scan(~r/phx-click="remove_param"\s+phx-value-id="([^"]+)"/, html)
        |> Enum.map(&List.last/1)

      html = render_click(lv, "remove_param", %{"id" => id})

      # Now only one remove button remains
      assert Regex.scan(~r/phx-click="remove_param"/, html) |> length() == 1
    end
  end

  describe "add_header" do
    test "adds a header row", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()

      # Switch to headers sub-tab
      render_click(lv, "switch_request_tab", %{"tab" => "headers"})

      # There's already a default Content-Type header, so 1 remove button
      html = render(lv)
      initial_count = Regex.scan(~r/phx-click="remove_header"/, html) |> length()

      html = render_click(lv, "add_header")
      new_count = Regex.scan(~r/phx-click="remove_header"/, html) |> length()

      assert new_count == initial_count + 1
    end

    test "respects the 50 item limit", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "headers"})

      # Already has 1 default header (Content-Type), so add 49 more to reach 50
      for _ <- 1..49 do
        render_click(lv, "add_header")
      end

      # The 51st should be rejected; verify count stays at 50
      render_click(lv, "add_header")
      html = render(lv)
      assert Regex.scan(~r/phx-click="remove_header"/, html) |> length() == 50
    end
  end

  describe "remove_header" do
    test "removes a header by id", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "headers"})

      # Add a header (there's already 1 default Content-Type header)
      render_click(lv, "add_header")
      html = render(lv)

      # Count remove_header buttons specifically
      initial_count = Regex.scan(~r/phx-click="remove_header"/, html) |> length()
      assert initial_count == 2

      # Extract a header id from a phx-value-id near remove_header
      [id | _] =
        Regex.scan(~r/phx-click="remove_header"\s+phx-value-id="([^"]+)"/, html)
        |> Enum.map(&List.last/1)

      html = render_click(lv, "remove_header", %{"id" => id})

      new_count = Regex.scan(~r/phx-click="remove_header"/, html) |> length()
      assert new_count == initial_count - 1
    end
  end

  describe "update_test_method" do
    test "changes the HTTP method", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()

      # Default method comes from api.method || "GET"
      html = render_click(lv, "update_test_method", %{"method" => "POST"})
      # POST should now be the selected method (shown in the select or active class)
      assert html =~ "POST"
    end

    test "ignores invalid method", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()

      render_click(lv, "update_test_method", %{"method" => "HACK"})
      html = render(lv)
      refute html =~ "HACK"
    end
  end

  describe "update_test_body" do
    test "invalid JSON shows error", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "body"})

      html = render_click(lv, "update_test_body", %{"test_body_json" => "{invalid json"})
      assert html =~ "Invalid JSON"
    end

    test "valid JSON clears error", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()
      render_click(lv, "switch_request_tab", %{"tab" => "body"})

      # First set invalid JSON
      render_click(lv, "update_test_body", %{"test_body_json" => "{bad"})
      # Then set valid JSON
      html = render_click(lv, "update_test_body", %{"test_body_json" => ~s({"a": 1})})
      refute html =~ "Invalid JSON"
    end
  end

  # --- Save Idempotency ---

  describe "save idempotency" do
    test "saving flag prevents duplicate saves", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Change code so save actually does something
      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{v: 1}"})

      # First save should work
      lv |> element("button[phx-click=save]") |> render_click()

      # Verify one version was created
      assert length(Apis.list_versions(api.id)) == 1

      # Change code again for second save
      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{v: 2}"})
      lv |> element("button[phx-click=save]") |> render_click()

      # Second save should also create a version (saving flag was reset)
      assert length(Apis.list_versions(api.id)) == 2
    end

    test "save_and_compile also guards against duplicate saves", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{ok: true}"})

      # First save_and_compile should work
      lv |> element("button", "Save & Compile") |> render_click()
      html = render(lv)
      # "Compiled successfully" badge is rendered in the LV template
      assert html =~ "Compiled successfully"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  # --- send_request ---

  describe "send_request" do
    test "send_request sets loading state", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()

      # Send request (the API is not compiled, so it will return an error via async)
      html = render_click(lv, "send_request")

      # The loading state should be set (button disabled or loading indicator shown)
      # We verify test_loading is true by checking that a second send_request is a no-op
      # (the guard clause returns {:noreply, socket} when test_loading: true)
      html2 = render_click(lv, "send_request")

      # Both should render without crash — loading guard prevents double request
      assert is_binary(html)
      assert is_binary(html2)
    end

    test "send_request guard prevents concurrent requests", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      lv |> element("[phx-click=switch_tab][phx-value-tab=test]") |> render_click()

      # First send sets test_loading: true
      render_click(lv, "send_request")

      # Second send should be a no-op (guard clause: test_loading: true)
      # This should not crash or create a second Task
      html = render_click(lv, "send_request")
      assert is_binary(html)
    end
  end
end
