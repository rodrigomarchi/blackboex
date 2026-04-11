defmodule BlackboexWeb.Components.StatusHelpers do
  @moduledoc """
  Shared CSS class mappings for status indicators.

  All classes reference semantic CSS tokens defined in app.css.
  Token naming convention (maps to CSS vars in app.css):
  - API lifecycle: `bg-status-{name}`, `text-status-{name}-foreground`, `border-status-{name}`
  - Feedback: `bg-success`, `text-success-foreground`, `bg-warning`, `text-info`, etc.
  - Charts: `var(--color-chart-{n})` for SVG fills
  """

  @doc """
  Returns CSS classes for API lifecycle status badges.

  ## Examples

      api_status_classes("published")
      #=> "border-status-published bg-status-published/10 text-status-published-foreground"
  """
  @spec api_status_classes(String.t()) :: String.t()
  def api_status_classes("draft"),
    do: "border-status-draft bg-status-draft/10 text-status-draft-foreground"

  def api_status_classes("compiled"),
    do: "border-status-compiled bg-status-compiled/10 text-status-compiled-foreground"

  def api_status_classes("published"),
    do: "border-status-published bg-status-published/10 text-status-published-foreground"

  def api_status_classes("archived"),
    do: "border-status-archived bg-status-archived/10 text-status-archived-foreground"

  def api_status_classes(_), do: "border bg-muted text-muted-foreground"

  @doc """
  Returns CSS classes for API status border/text (used in editor toolbar, status bar).
  """
  @spec api_status_border(String.t()) :: String.t()
  def api_status_border("draft"), do: "border-status-draft text-status-draft-foreground"
  def api_status_border("compiled"), do: "border-status-compiled text-status-compiled-foreground"

  def api_status_border("published"),
    do: "border-status-published text-status-published-foreground"

  def api_status_border("archived"), do: "border-status-archived text-status-archived-foreground"
  def api_status_border(_), do: "border-border text-muted-foreground"

  @doc """
  Returns CSS classes for process state badges (pending, generating, running, etc.).
  """
  @spec process_status_classes(String.t()) :: String.t()
  def process_status_classes("pending"),
    do: "border-warning bg-warning/10 text-warning-foreground"

  def process_status_classes("generating"),
    do:
      "border-status-generating bg-status-generating/10 text-status-generating-foreground animate-pulse"

  def process_status_classes("validating"),
    do:
      "border-status-generating bg-status-generating/10 text-status-generating-foreground animate-pulse"

  def process_status_classes("running"), do: "border-info bg-info/10 text-info-foreground"
  def process_status_classes(_), do: "border bg-muted text-muted-foreground"

  @doc """
  Returns CSS classes for pass/fail/skip result badges.
  """
  @spec result_classes(String.t() | atom()) :: String.t()
  def result_classes(status) when status in ["pass", :pass, "passed"],
    do: "bg-success/10 text-success-foreground"

  def result_classes(status) when status in ["fail", :fail, "failed", "error"],
    do: "bg-destructive/10 text-destructive"

  def result_classes(status) when status in ["skip", :skip, "skipped", "pending"],
    do: "bg-muted text-muted-foreground"

  def result_classes(_), do: "bg-muted text-muted-foreground"

  @doc """
  Returns CSS classes for subscription/billing status.
  """
  @spec subscription_classes(String.t()) :: String.t()
  def subscription_classes("active"), do: "border-success bg-success/10 text-success-foreground"
  def subscription_classes("trialing"), do: "border-info bg-info/10 text-info-foreground"
  def subscription_classes("past_due"), do: "border-warning bg-warning/10 text-warning-foreground"

  def subscription_classes("canceled"),
    do: "border-destructive bg-destructive/10 text-destructive"

  def subscription_classes("incomplete"),
    do: "border-warning bg-warning/10 text-warning-foreground"

  def subscription_classes(_), do: "border bg-muted text-muted-foreground"

  @doc """
  Returns CSS classes for API key status badges.
  """
  @spec api_key_status_classes(String.t()) :: String.t()
  def api_key_status_classes("Active"), do: "bg-status-active/10 text-status-active-foreground"
  def api_key_status_classes("Expired"), do: "bg-status-expired/10 text-status-expired-foreground"
  def api_key_status_classes("Revoked"), do: "bg-destructive/10 text-destructive"
  def api_key_status_classes(_), do: "bg-muted text-muted-foreground"

  # ── Schema field type colors ───────────────────────────────────────────

  @doc """
  Returns CSS class for schema field type indicators.

  ## Examples

      field_type_classes("string")  #=> "text-type-string-foreground"
      field_type_classes("integer") #=> "text-type-number-foreground"
  """
  @spec field_type_classes(String.t()) :: String.t()
  def field_type_classes("string"), do: "text-type-string-foreground"
  def field_type_classes("integer"), do: "text-type-number-foreground"
  def field_type_classes("number"), do: "text-type-number-foreground"
  def field_type_classes("float"), do: "text-type-number-foreground"
  def field_type_classes("boolean"), do: "text-type-boolean-foreground"
  def field_type_classes("array"), do: "text-type-array-foreground"
  def field_type_classes("object"), do: "text-type-object-foreground"
  def field_type_classes(_), do: "text-muted-foreground"

  # ── Execution status ───────────────────────────────────────────────────

  @doc """
  Returns CSS classes for flow execution status badges.

  ## Examples

      execution_status_classes("completed") #=> "bg-status-completed/15 text-status-completed-foreground"
  """
  @spec execution_status_classes(String.t()) :: String.t()
  def execution_status_classes("completed"),
    do: "bg-status-completed/15 text-status-completed-foreground"

  def execution_status_classes("success"),
    do: "bg-status-completed/15 text-status-completed-foreground"

  def execution_status_classes("running"),
    do: "bg-status-running/15 text-status-running-foreground"

  def execution_status_classes("failed"),
    do: "bg-status-failed/15 text-status-failed-foreground"

  def execution_status_classes("error"),
    do: "bg-status-failed/15 text-status-failed-foreground"

  def execution_status_classes("pending"),
    do: "bg-status-pending/15 text-status-pending-foreground"

  def execution_status_classes("cancelled"),
    do: "bg-status-cancelled/15 text-status-cancelled-foreground"

  def execution_status_classes("halted"),
    do: "bg-status-halted/15 text-status-halted-foreground"

  def execution_status_classes("skipped"),
    do: "bg-status-skipped/15 text-status-skipped-foreground"

  def execution_status_classes("compensated"),
    do: "bg-warning/15 text-warning-foreground"

  def execution_status_classes(_), do: "bg-muted text-muted-foreground"

  @doc """
  Returns CSS class for execution status dot (solid background circle).

  ## Examples

      execution_status_dot("completed") #=> "bg-status-completed"
      execution_status_dot("running")   #=> "bg-status-running animate-pulse"
  """
  @spec execution_status_dot(String.t()) :: String.t()
  def execution_status_dot("completed"), do: "bg-status-completed"
  def execution_status_dot("success"), do: "bg-status-completed"
  def execution_status_dot("running"), do: "bg-status-running animate-pulse"
  def execution_status_dot("failed"), do: "bg-status-failed"
  def execution_status_dot("error"), do: "bg-status-failed"
  def execution_status_dot("pending"), do: "bg-status-pending"
  def execution_status_dot("cancelled"), do: "bg-status-cancelled"
  def execution_status_dot("halted"), do: "bg-status-halted"
  def execution_status_dot("skipped"), do: "bg-status-skipped"
  def execution_status_dot("compensated"), do: "bg-warning"
  def execution_status_dot(_), do: "bg-muted-foreground"

  @doc """
  Returns CSS text color class for execution status (used in tables and detail views).

  ## Examples

      execution_status_text_class("completed") #=> "text-status-completed-foreground"
  """
  @spec execution_status_text_class(String.t()) :: String.t()
  def execution_status_text_class("completed"), do: "text-status-completed-foreground"
  def execution_status_text_class("success"), do: "text-status-completed-foreground"
  def execution_status_text_class("failed"), do: "text-status-failed-foreground"
  def execution_status_text_class("error"), do: "text-status-failed-foreground"
  def execution_status_text_class("running"), do: "text-status-running-foreground"
  def execution_status_text_class("halted"), do: "text-status-halted-foreground"
  def execution_status_text_class(_), do: "text-muted-foreground"

  # ── Charts ─────────────────────────────────────────────────────────────

  @doc """
  Returns CSS custom property reference for SVG chart elements.
  Responds to theme changes automatically.
  """
  @spec chart_color(atom()) :: String.t()
  def chart_color(:primary), do: "var(--color-chart-1)"
  def chart_color(:error), do: "var(--color-chart-4)"
  def chart_color(:warning), do: "var(--color-chart-3)"
  def chart_color(:success), do: "var(--color-chart-2)"
  def chart_color(:accent), do: "var(--color-chart-5)"
  def chart_color(:axis), do: "currentColor"
  def chart_color(_), do: "var(--color-chart-1)"
end
