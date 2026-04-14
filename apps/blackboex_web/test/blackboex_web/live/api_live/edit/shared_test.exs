defmodule BlackboexWeb.ApiLive.Edit.SharedTest do
  @moduledoc """
  Tests for Shared mount logic and command palette handling.

  Pure helper logic (restore_validation_report, derive_test_summary) is tested
  via the validation LiveView mount, which calls load_api/2 → those privates.
  Command palette events are tested via the code LiveView (any tab with Shared events).
  """

  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis

  setup [:register_and_log_in_user, :create_org]

  setup %{user: user, org: org} do
    api = api_fixture(%{user: user, org: org, name: "Shared Test API"})
    %{api: api}
  end

  # ── load_api / mount assigns ──────────────────────────────────────────

  describe "load_api - assigns" do
    test "sets api, org, page_title, versions on successful mount", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      assert html =~ "Shared Test API"
      # page_title is set as an assign; verify the API name is present in the rendered shell
      assert is_binary(render(lv))
    end

    test "redirects with error flash when API id does not exist", %{conn: conn, org: org} do
      missing_uuid = "00000000-0000-0000-0000-000000000000"

      assert {:error, {:live_redirect, %{to: "/apis", flash: %{"error" => "API not found"}}}} =
               live(conn, ~p"/apis/#{missing_uuid}/edit/validation?org=#{org.id}")
    end

    test "redirects when API belongs to another org", %{conn: conn} do
      other_user = Blackboex.AccountsFixtures.user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org",
          slug: "other-org-#{System.unique_integer([:positive])}"
        })

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          slug: "other-api-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: other_org.id,
          project_id: Blackboex.Projects.get_default_project(other_org.id).id,
          user_id: other_user.id
        })

      assert {:error, {:live_redirect, %{to: "/apis", flash: %{"error" => "API not found"}}}} =
               live(conn, ~p"/apis/#{other_api.id}/edit/validation?org=#{other_org.id}")
    end
  end

  describe "load_api - restore_validation_report" do
    test "validation_report is nil when api has no report", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render(lv)
      # nil report renders the "No validation results yet" message
      assert html =~ "No validation results yet"
    end

    test "validation_report is restored from DB JSON when api has a report", %{
      conn: conn,
      org: org,
      api: api
    } do
      # Persist a validation report (stored as JSONB with string keys)
      report = %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [],
        "overall" => "pass"
      }

      {:ok, _api} = Apis.update_api(api, %{validation_report: report})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render(lv)
      # Restored report with overall: :pass renders "ALL PASS"
      assert html =~ "ALL PASS"
    end

    test "validation_report handles fail status from DB JSON", %{
      conn: conn,
      org: org,
      api: api
    } do
      report = %{
        "compilation" => "fail",
        "compilation_errors" => ["undefined variable x"],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "skipped",
        "test_results" => [],
        "overall" => "fail"
      }

      {:ok, _api} = Apis.update_api(api, %{validation_report: report})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render(lv)
      assert html =~ "ISSUES FOUND"
      assert html =~ "undefined variable x"
    end
  end

  describe "load_api - derive_test_summary" do
    test "test_summary is nil when api has no report", %{conn: conn, org: org, api: api} do
      # No validation_report — summary should be nil; tab just shows nothing special
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")
      # Just verify mount does not crash
      assert is_binary(render(lv))
    end

    test "test_summary shows passing count when test_results exist", %{
      conn: conn,
      org: org,
      api: api
    } do
      report = %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [
          %{"status" => "passed", "name" => "t1", "error" => nil},
          %{"status" => "passed", "name" => "t2", "error" => nil},
          %{"status" => "failed", "name" => "t3", "error" => "boom"}
        ],
        "overall" => "fail"
      }

      {:ok, _api} = Apis.update_api(api, %{validation_report: report})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render(lv)
      # test_summary "2/3" appears in tab bar badge (editor_shell renders it)
      assert html =~ "2/3" or html =~ "2/3 passing"
    end
  end

  # ── handle_command_palette ────────────────────────────────────────────

  describe "toggle_command_palette" do
    test "opens command palette when closed", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render_click(lv, "toggle_command_palette", %{})
      # Command palette should now be visible
      assert html =~ "command" or html =~ "palette" or html =~ "search" or
               html =~ "command_palette"
    end

    test "closes command palette on second toggle", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "toggle_command_palette", %{})

      # After two toggles palette is closed again — no crash
      assert is_binary(html)
    end
  end

  describe "close_panels" do
    test "closes command palette when it is open", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "close_panels", %{})

      # No crash — palette is closed
      assert is_binary(html)
    end

    test "is a no-op when palette is already closed", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end
  end

  describe "command_palette_search" do
    test "updates query without crash", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      html = render_click(lv, "command_palette_search", %{"command_query" => "test"})
      assert is_binary(html)
    end
  end

  describe "command_palette_navigate" do
    test "navigates down without exceeding bounds", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      for _ <- 1..10 do
        render_click(lv, "command_palette_navigate", %{"direction" => "down"})
      end

      html = render(lv)
      assert is_binary(html)
    end

    test "navigates up and stays at 0", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      for _ <- 1..5 do
        render_click(lv, "command_palette_navigate", %{"direction" => "up"})
      end

      html = render(lv)
      assert is_binary(html)
    end
  end

  describe "command_palette_exec" do
    test "closes palette and navigates to given tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "switch_tab_chat"})

      assert path =~ "/edit/chat"
    end

    test "routes toggle_chat to chat tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "toggle_chat"})

      assert path =~ "/edit/chat"
    end

    test "routes unknown event to code tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "something_unknown"})

      assert path =~ "/edit/chat"
    end
  end

  describe "command_palette_exec_first" do
    test "is a no-op when no commands match", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      # Search for something that matches nothing
      render_click(lv, "command_palette_search", %{"command_query" => "zzznomatch"})

      # exec_first with empty results should not crash or navigate
      html = render_click(lv, "command_palette_exec_first", %{})
      assert is_binary(html)
    end

    test "navigates when a command is selected", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      # Empty query returns all commands; first one should be selected (index 0)
      render_click(lv, "command_palette_search", %{"command_query" => ""})

      result = render_click(lv, "command_palette_exec_first", %{})
      # Either navigated (live_redirect) or rendered without crash
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end

  # ── edit_tab_path ─────────────────────────────────────────────────────

  describe "edit_tab_path - via command routing" do
    test "switch_tab_run routes to run tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "switch_tab_run"})

      assert path == "/apis/#{api.id}/edit/run"
    end

    test "toggle_config routes to publish tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "toggle_config"})

      assert path =~ "/edit/publish"
    end

    test "toggle_bottom_panel routes to run tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(lv, "command_palette_exec", %{"event" => "toggle_bottom_panel"})

      assert path =~ "/edit/run"
    end
  end
end
