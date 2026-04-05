defmodule BlackboexWeb.Components.StatusHelpersTest do
  use ExUnit.Case, async: true

  alias BlackboexWeb.Components.StatusHelpers

  # ── api_status_classes ────────────────────────────────────────────────

  describe "api_status_classes/1" do
    test "returns draft classes" do
      assert StatusHelpers.api_status_classes("draft") ==
               "border-status-draft bg-status-draft/10 text-status-draft-foreground"
    end

    test "returns compiled classes" do
      assert StatusHelpers.api_status_classes("compiled") ==
               "border-status-compiled bg-status-compiled/10 text-status-compiled-foreground"
    end

    test "returns published classes" do
      assert StatusHelpers.api_status_classes("published") ==
               "border-status-published bg-status-published/10 text-status-published-foreground"
    end

    test "returns archived classes" do
      assert StatusHelpers.api_status_classes("archived") ==
               "border-status-archived bg-status-archived/10 text-status-archived-foreground"
    end

    test "returns fallback classes for unknown status" do
      assert StatusHelpers.api_status_classes("unknown") == "border bg-muted text-muted-foreground"
      assert StatusHelpers.api_status_classes("") == "border bg-muted text-muted-foreground"
      assert StatusHelpers.api_status_classes("DRAFT") == "border bg-muted text-muted-foreground"
    end
  end

  # ── api_status_border ─────────────────────────────────────────────────

  describe "api_status_border/1" do
    test "returns draft border classes" do
      assert StatusHelpers.api_status_border("draft") ==
               "border-status-draft text-status-draft-foreground"
    end

    test "returns compiled border classes" do
      assert StatusHelpers.api_status_border("compiled") ==
               "border-status-compiled text-status-compiled-foreground"
    end

    test "returns published border classes" do
      assert StatusHelpers.api_status_border("published") ==
               "border-status-published text-status-published-foreground"
    end

    test "returns archived border classes" do
      assert StatusHelpers.api_status_border("archived") ==
               "border-status-archived text-status-archived-foreground"
    end

    test "returns fallback border classes for unknown status" do
      assert StatusHelpers.api_status_border("unknown") ==
               "border-border text-muted-foreground"

      assert StatusHelpers.api_status_border("") == "border-border text-muted-foreground"
    end
  end

  # ── process_status_classes ────────────────────────────────────────────

  describe "process_status_classes/1" do
    test "returns warning classes for pending" do
      assert StatusHelpers.process_status_classes("pending") ==
               "border-warning bg-warning/10 text-warning-foreground"
    end

    test "returns generating classes with animate-pulse for generating" do
      result = StatusHelpers.process_status_classes("generating")
      assert result =~ "animate-pulse"
      assert result =~ "border-status-generating"
    end

    test "returns same generating classes for validating" do
      assert StatusHelpers.process_status_classes("validating") ==
               StatusHelpers.process_status_classes("generating")
    end

    test "returns info classes for running" do
      assert StatusHelpers.process_status_classes("running") ==
               "border-info bg-info/10 text-info-foreground"
    end

    test "returns fallback classes for unknown process status" do
      assert StatusHelpers.process_status_classes("idle") ==
               "border bg-muted text-muted-foreground"

      assert StatusHelpers.process_status_classes("") == "border bg-muted text-muted-foreground"
    end
  end

  # ── result_classes ────────────────────────────────────────────────────

  describe "result_classes/1" do
    test "returns success classes for pass variants" do
      expected = "bg-success/10 text-success-foreground"
      assert StatusHelpers.result_classes("pass") == expected
      assert StatusHelpers.result_classes(:pass) == expected
      assert StatusHelpers.result_classes("passed") == expected
    end

    test "returns destructive classes for fail variants" do
      expected = "bg-destructive/10 text-destructive"
      assert StatusHelpers.result_classes("fail") == expected
      assert StatusHelpers.result_classes(:fail) == expected
      assert StatusHelpers.result_classes("failed") == expected
      assert StatusHelpers.result_classes("error") == expected
    end

    test "returns muted classes for skip variants" do
      expected = "bg-muted text-muted-foreground"
      assert StatusHelpers.result_classes("skip") == expected
      assert StatusHelpers.result_classes(:skip) == expected
      assert StatusHelpers.result_classes("skipped") == expected
      assert StatusHelpers.result_classes("pending") == expected
    end

    test "returns muted classes for unknown result" do
      assert StatusHelpers.result_classes("unknown") == "bg-muted text-muted-foreground"
      assert StatusHelpers.result_classes("") == "bg-muted text-muted-foreground"
    end
  end

  # ── subscription_classes ──────────────────────────────────────────────

  describe "subscription_classes/1" do
    test "returns success classes for active" do
      assert StatusHelpers.subscription_classes("active") ==
               "border-success bg-success/10 text-success-foreground"
    end

    test "returns info classes for trialing" do
      assert StatusHelpers.subscription_classes("trialing") ==
               "border-info bg-info/10 text-info-foreground"
    end

    test "returns warning classes for past_due" do
      assert StatusHelpers.subscription_classes("past_due") ==
               "border-warning bg-warning/10 text-warning-foreground"
    end

    test "returns destructive classes for canceled" do
      assert StatusHelpers.subscription_classes("canceled") ==
               "border-destructive bg-destructive/10 text-destructive"
    end

    test "returns warning classes for incomplete" do
      assert StatusHelpers.subscription_classes("incomplete") ==
               "border-warning bg-warning/10 text-warning-foreground"
    end

    test "returns fallback classes for unknown subscription status" do
      assert StatusHelpers.subscription_classes("expired") ==
               "border bg-muted text-muted-foreground"

      assert StatusHelpers.subscription_classes("") == "border bg-muted text-muted-foreground"
    end
  end

  # ── api_key_status_classes ────────────────────────────────────────────

  describe "api_key_status_classes/1" do
    test "returns active classes for Active" do
      assert StatusHelpers.api_key_status_classes("Active") ==
               "bg-status-active/10 text-status-active-foreground"
    end

    test "returns expired classes for Expired" do
      assert StatusHelpers.api_key_status_classes("Expired") ==
               "bg-status-expired/10 text-status-expired-foreground"
    end

    test "returns destructive classes for Revoked" do
      assert StatusHelpers.api_key_status_classes("Revoked") ==
               "bg-destructive/10 text-destructive"
    end

    test "returns fallback classes for unknown key status" do
      assert StatusHelpers.api_key_status_classes("active") ==
               "bg-muted text-muted-foreground"

      assert StatusHelpers.api_key_status_classes("") == "bg-muted text-muted-foreground"
    end
  end

  # ── chart_color ───────────────────────────────────────────────────────

  describe "chart_color/1" do
    test "returns chart-1 for :primary" do
      assert StatusHelpers.chart_color(:primary) == "var(--color-chart-1)"
    end

    test "returns chart-4 for :error" do
      assert StatusHelpers.chart_color(:error) == "var(--color-chart-4)"
    end

    test "returns chart-3 for :warning" do
      assert StatusHelpers.chart_color(:warning) == "var(--color-chart-3)"
    end

    test "returns chart-2 for :success" do
      assert StatusHelpers.chart_color(:success) == "var(--color-chart-2)"
    end

    test "returns chart-5 for :accent" do
      assert StatusHelpers.chart_color(:accent) == "var(--color-chart-5)"
    end

    test "returns currentColor for :axis" do
      assert StatusHelpers.chart_color(:axis) == "currentColor"
    end

    test "returns chart-1 as fallback for unknown atoms" do
      assert StatusHelpers.chart_color(:unknown) == "var(--color-chart-1)"
      assert StatusHelpers.chart_color(:other) == "var(--color-chart-1)"
    end
  end
end
