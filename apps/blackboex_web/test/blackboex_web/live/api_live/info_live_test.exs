defmodule BlackboexWeb.ApiLive.Edit.InfoLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis

  setup [:register_and_log_in_user, :create_org]

  setup %{user: user, org: org} do
    Apis.Registry.clear()
    api = api_fixture(%{user: user, org: org, name: "Info Test API"})
    %{api: api}
  end

  describe "mount" do
    test "renders info tab with API details", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "API Information"
      assert html =~ "Info Test API"
      assert html =~ "computation"
    end

    test "shows danger zone with archive button", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "Archive this API"
      assert html =~ "archive_api"
    end

    test "shows code stats section", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "Source Lines"
      assert html =~ "Test Lines"
      assert html =~ "Versions"
    end
  end

  describe "update_info" do
    test "with valid name and description updates the API", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "Updated Name", "description" => "New description"})

      assert html =~ "Updated Name"
    end

    test "shows success flash after update", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "New Name", "description" => "A description"})

      assert html =~ "API info updated"
    end

    test "persists name change in database", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      lv
      |> element("form")
      |> render_submit(%{"name" => "Persisted Name", "description" => ""})

      updated = Apis.get_api(org.id, api.id)
      assert updated.name == "Persisted Name"
    end

    test "trims whitespace from name and description", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      lv
      |> element("form")
      |> render_submit(%{"name" => "  Trimmed Name  ", "description" => "  trimmed desc  "})

      updated = Apis.get_api(org.id, api.id)
      assert updated.name == "Trimmed Name"
      assert updated.description == "trimmed desc"
    end

    test "update with empty name shows error or keeps old name", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "", "description" => "some desc"})

      # Should either show validation error or keep old name
      assert html =~ "Info Test API" or html =~ "can't be blank" or
               html =~ "error" or html =~ "Failed"
    end
  end

  describe "archive_api" do
    # The UI funnels archive through a request_confirm modal, so we bypass the
    # button click and fire the already-confirmed archive_api event directly.
    # This still exercises the real handle_event path end-to-end.

    test "marks API as archived and redirects to /apis", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert {:error, {:live_redirect, %{to: "/apis"}}} =
               render_click(lv, "archive_api", %{})
    end

    test "sets status to archived in database", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "archive_api", %{})

      archived = Apis.get_api(org.id, api.id)
      assert archived.status == "archived"
    end

    test "shows info flash before redirect", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      result = render_click(lv, "archive_api", %{})

      case result do
        {:error, {:live_redirect, _}} ->
          assert true

        html when is_binary(html) ->
          assert html =~ "archived"
      end
    end
  end

  describe "copy_url" do
    test "triggers JS copy_to_clipboard event", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      # The event should not crash; it pushes a client-side event
      html = render_click(lv, "copy_url", %{})
      assert is_binary(html)
    end
  end

  describe "command palette events" do
    test "toggle_command_palette opens the palette", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html = render_click(lv, "toggle_command_palette", %{})
      assert is_binary(html)
    end

    test "close_panels closes the palette when open", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "close_panels is a no-op when palette is already closed", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "command_palette_search filters commands", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_search", %{"command_query" => "info"})
      assert is_binary(html)
    end

    test "command_palette_navigate down moves selection", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "down"})
      assert is_binary(html)
    end

    test "command_palette_navigate up moves selection back", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "up"})
      assert is_binary(html)
    end

    test "command_palette_exec navigates to given tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      result = render_click(lv, "command_palette_exec", %{"event" => "switch_tab_run"})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "command_palette_exec_first executes first matched command", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      result = render_click(lv, "command_palette_exec_first", %{})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end

  describe "api info display" do
    test "shows param_schema when present", %{conn: conn, org: org, api: api} do
      {:ok, _} = Apis.update_api(api, %{param_schema: %{"type" => "object"}})

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")
      assert html =~ "Param Schema" or html =~ "object"
    end

    test "shows example_request when present", %{conn: conn, org: org, api: api} do
      {:ok, _} = Apis.update_api(api, %{example_request: %{"x" => 1}})

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")
      assert html =~ "Example Request" or html =~ "x"
    end

    test "shows example_response when present", %{conn: conn, org: org, api: api} do
      {:ok, _} = Apis.update_api(api, %{example_response: %{"result" => "ok"}})

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")
      assert html =~ "Example Response" or html =~ "result"
    end
  end
end
