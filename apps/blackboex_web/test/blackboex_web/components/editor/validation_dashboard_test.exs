defmodule BlackboexWeb.Components.Editor.ValidationDashboardTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  import BlackboexWeb.Components.Editor.ValidationDashboard

  # ── validation_dashboard/1 ────────────────────────────────────────────

  describe "validation_dashboard/1 - loading state" do
    test "shows spinner and loading text when loading: true" do
      html = render_component(&validation_dashboard/1, report: nil, loading: true)

      assert html =~ "Running validations"
      assert html =~ "animate-spin"
    end

    test "does not show report content when loading" do
      report = all_pass_report()
      html = render_component(&validation_dashboard/1, report: report, loading: true)

      refute html =~ "ALL PASS"
      refute html =~ "Compilation"
    end
  end

  describe "validation_dashboard/1 - nil report" do
    test "shows 'no validation results' message when report is nil and not loading" do
      html = render_component(&validation_dashboard/1, report: nil, loading: false)

      assert html =~ "No validation results yet"
      assert html =~ "Save to run validations"
    end

    test "does not show spinner when not loading" do
      html = render_component(&validation_dashboard/1, report: nil, loading: false)

      refute html =~ "animate-spin"
    end
  end

  describe "validation_dashboard/1 - all pass report" do
    test "shows ALL PASS badge" do
      html = render_component(&validation_dashboard/1, report: all_pass_report(), loading: false)

      assert html =~ "ALL PASS"
    end

    test "renders all four check sections" do
      html = render_component(&validation_dashboard/1, report: all_pass_report(), loading: false)

      assert html =~ "Compilation"
      assert html =~ "Format"
      assert html =~ "Credo"
      assert html =~ "Tests"
    end

    test "shows pass icon (checkmark) for all sections" do
      html = render_component(&validation_dashboard/1, report: all_pass_report(), loading: false)

      # pass icon is ✓
      assert html =~ "✓"
    end

    test "shows passing test count" do
      report = %{all_pass_report() | test_results: passing_test_results(2)}
      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "2/2 passing"
    end
  end

  describe "validation_dashboard/1 - mixed pass/fail report" do
    test "shows ISSUES FOUND badge when overall is :fail" do
      html = render_component(&validation_dashboard/1, report: mixed_report(), loading: false)

      assert html =~ "ISSUES FOUND"
    end

    test "shows fail icon (✗) when compilation fails" do
      html = render_component(&validation_dashboard/1, report: mixed_report(), loading: false)

      assert html =~ "✗"
    end

    test "shows compilation errors list" do
      report = %{
        all_pass_report()
        | compilation: :fail,
          compilation_errors: ["undefined variable x", "syntax error near do"],
          overall: :fail
      }

      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "undefined variable x"
      assert html =~ "syntax error near do"
      assert html =~ "2 issues"
    end

    test "shows single issue with singular label" do
      report = %{
        all_pass_report()
        | credo: :fail,
          credo_issues: ["Module doc missing"],
          overall: :fail
      }

      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "1 issue"
      refute html =~ "1 issues"
    end

    test "shows format issues" do
      report = %{
        all_pass_report()
        | format: :fail,
          format_issues: ["line 5 needs formatting"],
          overall: :fail
      }

      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "line 5 needs formatting"
    end
  end

  describe "validation_dashboard/1 - test section" do
    test "shows skipped label when tests status is :skipped" do
      report = %{all_pass_report() | tests: :skipped, test_results: []}
      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "skipped"
    end

    test "shows individual test pass/fail markers" do
      results = [
        %{status: "passed", name: "adds numbers", error: nil},
        %{status: "failed", name: "divides by zero", error: "ArithmeticError"}
      ]

      report = %{all_pass_report() | tests: :fail, test_results: results, overall: :fail}
      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "adds numbers"
      assert html =~ "divides by zero"
      assert html =~ "ArithmeticError"
      assert html =~ "1/2 passing"
    end

    test "handles string-keyed test results (DB JSONB format)" do
      results = [
        %{"status" => "passed", "name" => "test one", "error" => nil},
        %{"status" => "failed", "name" => "test two", "error" => "boom"}
      ]

      report = %{all_pass_report() | tests: :fail, test_results: results, overall: :fail}
      html = render_component(&validation_dashboard/1, report: report, loading: false)

      assert html =~ "test one"
      assert html =~ "test two"
      assert html =~ "boom"
    end
  end

  # ── validation_badge/1 ────────────────────────────────────────────────

  describe "validation_badge/1" do
    test "renders check name" do
      html = render_component(&validation_badge/1, check: "Compilation", status: :pass)

      assert html =~ "Compilation"
    end

    test "renders pass icon for :pass status" do
      html = render_component(&validation_badge/1, check: "Format", status: :pass)

      assert html =~ "✓"
    end

    test "renders fail icon for :fail status" do
      html = render_component(&validation_badge/1, check: "Credo", status: :fail)

      assert html =~ "✗"
    end

    test "renders skipped icon for :skipped status" do
      html = render_component(&validation_badge/1, check: "Tests", status: :skipped)

      assert html =~ "—"
    end

    test "renders warn icon for :warn status" do
      html = render_component(&validation_badge/1, check: "Lint", status: :warn)

      assert html =~ "⚠"
    end

    test "renders unknown status with circle icon" do
      html = render_component(&validation_badge/1, check: "Unknown", status: :unknown)

      assert html =~ "○"
    end

    test "renders optional detail when provided" do
      html =
        render_component(&validation_badge/1,
          check: "Tests",
          status: :pass,
          detail: "3/3"
        )

      assert html =~ "3/3"
    end

    test "renders without detail by default" do
      html = render_component(&validation_badge/1, check: "Tests", status: :pass)

      refute html =~ "nil"
    end
  end

  # ── Fixtures ──────────────────────────────────────────────────────────

  defp all_pass_report do
    %{
      overall: :pass,
      compilation: :pass,
      compilation_errors: [],
      format: :pass,
      format_issues: [],
      credo: :pass,
      credo_issues: [],
      tests: :pass,
      test_results: []
    }
  end

  defp mixed_report do
    %{
      overall: :fail,
      compilation: :fail,
      compilation_errors: ["error on line 1"],
      format: :pass,
      format_issues: [],
      credo: :pass,
      credo_issues: [],
      tests: :pass,
      test_results: []
    }
  end

  defp passing_test_results(count) do
    for i <- 1..count do
      %{status: "passed", name: "test #{i}", error: nil}
    end
  end
end
