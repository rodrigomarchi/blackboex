defmodule BlackboexWeb.ApiLive.Edit.HelpersTest do
  use BlackboexWeb.ConnCase, async: true

  alias BlackboexWeb.ApiLive.Edit.Helpers

  # ── render_markdown ───────────────────────────────────────────────────

  describe "render_markdown/1" do
    test "returns empty string for nil" do
      assert Helpers.render_markdown(nil) == ""
    end

    test "converts simple markdown to HTML" do
      result = Helpers.render_markdown("# Hello")
      assert result =~ "<h1"
      assert result =~ "Hello"
    end

    test "converts bold markdown" do
      result = Helpers.render_markdown("**bold**")
      assert result =~ "<strong>" or result =~ "<b>"
    end

    test "converts a markdown table" do
      md = "| a | b |\n|---|---|\n| 1 | 2 |"
      result = Helpers.render_markdown(md)
      assert result =~ "<table"
    end

    test "returns the original markdown when conversion fails" do
      # An empty string is valid markdown, returns ""
      result = Helpers.render_markdown("")
      assert is_binary(result)
    end

    test "handles plain text without markup" do
      result = Helpers.render_markdown("just plain text")
      assert result =~ "just plain text"
    end
  end

  # ── time_ago ─────────────────────────────────────────────────────────

  describe "time_ago/1" do
    test "returns 'never' for nil" do
      assert Helpers.time_ago(nil) == "never"
    end

    test "returns 'unknown' for non-datetime values" do
      assert Helpers.time_ago("not a datetime") == "unknown"
      assert Helpers.time_ago(42) == "unknown"
      assert Helpers.time_ago(%{}) == "unknown"
    end

    test "returns 'just now' for datetimes less than 60 seconds ago" do
      dt = NaiveDateTime.add(NaiveDateTime.utc_now(), -30, :second)
      assert Helpers.time_ago(dt) == "just now"
    end

    test "returns minutes ago for datetimes between 1 and 60 minutes ago" do
      dt = NaiveDateTime.add(NaiveDateTime.utc_now(), -300, :second)
      assert Helpers.time_ago(dt) == "5 min ago"
    end

    test "returns hours ago for datetimes between 1 hour and 24 hours ago" do
      dt = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      assert Helpers.time_ago(dt) == "2 hours ago"
    end

    test "returns days ago for datetimes more than 24 hours ago" do
      dt = NaiveDateTime.add(NaiveDateTime.utc_now(), -172_800, :second)
      assert Helpers.time_ago(dt) == "2 days ago"
    end
  end

  # ── count_lines ───────────────────────────────────────────────────────

  describe "count_lines/1" do
    test "returns 0 for nil" do
      assert Helpers.count_lines(nil) == 0
    end

    test "returns 0 for empty string" do
      assert Helpers.count_lines("") == 0
    end

    test "returns 1 for a single line with no newline" do
      assert Helpers.count_lines("one line") == 1
    end

    test "returns correct count for multi-line string" do
      assert Helpers.count_lines("line1\nline2\nline3") == 3
    end

    test "counts trailing newline as an extra line" do
      assert Helpers.count_lines("line1\nline2\n") == 3
    end
  end

  # ── format_json ───────────────────────────────────────────────────────

  describe "format_json/1" do
    test "returns empty string for nil" do
      assert Helpers.format_json(nil) == ""
    end

    test "formats a map as pretty-printed JSON" do
      result = Helpers.format_json(%{"key" => "value"})
      assert result =~ "\"key\""
      assert result =~ "\"value\""
    end

    test "formats nested maps" do
      result = Helpers.format_json(%{"a" => %{"b" => 1}})
      assert result =~ "\"a\""
      assert result =~ "\"b\""
    end

    test "uses inspect for non-map values" do
      assert Helpers.format_json([1, 2, 3]) == inspect([1, 2, 3])
      assert Helpers.format_json("string") == inspect("string")
      assert Helpers.format_json(42) == inspect(42)
    end
  end

  # ── history_status_color ──────────────────────────────────────────────

  describe "history_status_color/1" do
    test "returns success classes for 2xx status codes" do
      assert Helpers.history_status_color(200) == "bg-success/10 text-success-foreground"
      assert Helpers.history_status_color(201) == "bg-success/10 text-success-foreground"
      assert Helpers.history_status_color(299) == "bg-success/10 text-success-foreground"
    end

    test "returns warning classes for 4xx status codes" do
      assert Helpers.history_status_color(400) == "bg-warning/10 text-warning-foreground"
      assert Helpers.history_status_color(404) == "bg-warning/10 text-warning-foreground"
      assert Helpers.history_status_color(499) == "bg-warning/10 text-warning-foreground"
    end

    test "returns destructive classes for 5xx status codes" do
      assert Helpers.history_status_color(500) == "bg-destructive/10 text-destructive"
      assert Helpers.history_status_color(503) == "bg-destructive/10 text-destructive"
    end

    test "returns muted classes for unmatched status codes" do
      assert Helpers.history_status_color(100) == "bg-muted text-muted-foreground"
      assert Helpers.history_status_color(301) == "bg-muted text-muted-foreground"
    end
  end

  # ── test_summary_class ────────────────────────────────────────────────

  describe "test_summary_class/1" do
    test "returns success classes when all tests pass (passed == total)" do
      assert Helpers.test_summary_class("5/5") == "bg-success/10 text-success-foreground"
      assert Helpers.test_summary_class("1/1") == "bg-success/10 text-success-foreground"
    end

    test "returns destructive classes when some tests fail (passed != total)" do
      assert Helpers.test_summary_class("3/5") == "bg-destructive/10 text-destructive"
      assert Helpers.test_summary_class("0/3") == "bg-destructive/10 text-destructive"
    end

    test "returns muted classes for summaries without a slash" do
      assert Helpers.test_summary_class("no tests") == "bg-muted text-muted-foreground"
      assert Helpers.test_summary_class("") == "bg-muted text-muted-foreground"
    end
  end

  # ── restore_validation_report ─────────────────────────────────────────

  describe "restore_validation_report/1" do
    test "returns nil for nil input" do
      assert Helpers.restore_validation_report(nil) == nil
    end

    test "converts string keys to atom keys with atom status values" do
      report = %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "fail",
        "format_issues" => ["issue1"],
        "credo" => "skipped",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [],
        "overall" => "fail"
      }

      result = Helpers.restore_validation_report(report)

      assert result.compilation == :pass
      assert result.format == :fail
      assert result.credo == :skipped
      assert result.tests == :pass
      assert result.overall == :fail
      assert result.compilation_errors == []
      assert result.format_issues == ["issue1"]
    end

    test "defaults missing list fields to empty lists" do
      report = %{
        "compilation" => "pass",
        "format" => "pass",
        "credo" => "pass",
        "tests" => "pass",
        "overall" => "pass"
      }

      result = Helpers.restore_validation_report(report)

      assert result.compilation_errors == []
      assert result.format_issues == []
      assert result.credo_issues == []
      assert result.test_results == []
    end

    test "defaults unknown status strings to :pass" do
      report = %{
        "compilation" => "unknown_value",
        "format" => nil,
        "credo" => "pass",
        "tests" => "pass",
        "overall" => "pass"
      }

      result = Helpers.restore_validation_report(report)
      assert result.compilation == :pass
      assert result.format == :pass
    end
  end

  # ── derive_test_summary ───────────────────────────────────────────────

  describe "derive_test_summary/1" do
    test "returns nil for nil input" do
      assert Helpers.derive_test_summary(nil) == nil
    end

    test "returns nil when test_results is missing or empty" do
      assert Helpers.derive_test_summary(%{}) == nil
      assert Helpers.derive_test_summary(%{"test_results" => []}) == nil
    end

    test "counts passed tests using string keys" do
      report = %{
        "test_results" => [
          %{"status" => "passed"},
          %{"status" => "passed"},
          %{"status" => "failed"}
        ]
      }

      assert Helpers.derive_test_summary(report) == "2/3"
    end

    test "counts passed tests using atom keys" do
      report = %{
        "test_results" => [
          %{status: "passed"},
          %{status: "failed"},
          %{status: "failed"}
        ]
      }

      assert Helpers.derive_test_summary(report) == "1/3"
    end

    test "returns '0/N' when no tests pass" do
      report = %{
        "test_results" => [
          %{"status" => "failed"},
          %{"status" => "failed"}
        ]
      }

      assert Helpers.derive_test_summary(report) == "0/2"
    end

    test "returns 'N/N' when all tests pass" do
      report = %{
        "test_results" => [
          %{"status" => "passed"},
          %{"status" => "passed"}
        ]
      }

      assert Helpers.derive_test_summary(report) == "2/2"
    end
  end

  # ── edit_tab_path ─────────────────────────────────────────────────────

  describe "edit_tab_path/2" do
    test "builds path with api id and tab" do
      # Build a minimal socket-like struct with an api assign
      api_id = Ecto.UUID.generate()
      socket = %Phoenix.LiveView.Socket{assigns: %{api: %{id: api_id}}}

      assert Helpers.edit_tab_path(socket, "run") == "/apis/#{api_id}/edit/run"
      assert Helpers.edit_tab_path(socket, "metrics") == "/apis/#{api_id}/edit/metrics"
      assert Helpers.edit_tab_path(socket, "info") == "/apis/#{api_id}/edit/info"
      assert Helpers.edit_tab_path(socket, "docs") == "/apis/#{api_id}/edit/docs"
    end
  end

  # ── resolve_organization ──────────────────────────────────────────────

  describe "resolve_organization/2" do
    setup :register_and_log_in_user

    test "returns scope.organization when no org param", %{scope: scope} do
      # Build a minimal socket with current_scope
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: scope}}

      org = Helpers.resolve_organization(socket, %{})
      assert org == scope.organization
    end

    test "returns the organization when org param matches and user is a member", %{
      conn: _conn,
      user: user,
      scope: scope
    } do
      {:ok, %{organization: org}} =
        Blackboex.Organizations.create_organization(user, %{
          name: "Helpers Org #{System.unique_integer([:positive])}",
          slug: "helpersorg-#{System.unique_integer([:positive])}"
        })

      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: scope}}
      result = Helpers.resolve_organization(socket, %{"org" => org.id})

      assert result.id == org.id
    end

    test "returns nil when org param points to non-existent organization", %{scope: scope} do
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: scope}}
      result = Helpers.resolve_organization(socket, %{"org" => Ecto.UUID.generate()})
      assert result == nil
    end

    test "returns nil when user is not a member of the given org", %{scope: scope, user: _user} do
      # Create an org owned by a different user
      other_user = Blackboex.AccountsFixtures.user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org #{System.unique_integer([:positive])}",
          slug: "otherorg-#{System.unique_integer([:positive])}"
        })

      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: scope}}
      result = Helpers.resolve_organization(socket, %{"org" => other_org.id})
      assert result == nil
    end
  end
end
