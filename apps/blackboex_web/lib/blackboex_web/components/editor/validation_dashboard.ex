defmodule BlackboexWeb.Components.Editor.ValidationDashboard do
  @moduledoc """
  Dashboard component showing results of all validation checks:
  compilation, format, Credo, and tests.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge

  attr :report, :map, default: nil
  attr :loading, :boolean, default: false

  @spec validation_dashboard(map()) :: Phoenix.LiveView.Rendered.t()
  def validation_dashboard(assigns) do
    ~H"""
    <div :if={@loading} class="flex items-center gap-2 text-muted-description p-4">
      <.icon name="hero-arrow-path" class="size-4 animate-spin" />
      <span>Running validations...</span>
    </div>

    <div :if={!@loading && @report == nil} class="p-4 text-muted-description">
      No validation results yet. Save to run validations.
    </div>

    <div :if={!@loading && @report != nil} class="space-y-3 p-3">
      <%!-- Overall badge --%>
      <div class="flex items-center gap-2">
        <.badge variant={if @report.overall == :pass, do: "success", else: "destructive"}>
          {if @report.overall == :pass, do: "ALL PASS", else: "ISSUES FOUND"}
        </.badge>
      </div>

      <%!-- Compilation --%>
      <.check_section
        name="Compilation"
        status={@report.compilation}
        issues={@report.compilation_errors}
      />

      <%!-- Format --%>
      <.check_section
        name="Format"
        status={@report.format}
        issues={@report.format_issues}
      />

      <%!-- Credo --%>
      <.check_section
        name="Credo"
        status={@report.credo}
        issues={@report.credo_issues}
      />

      <%!-- Tests --%>
      <.test_section
        status={@report.tests}
        results={@report.test_results}
      />
    </div>
    """
  end

  attr :check, :string, required: true
  attr :status, :atom, required: true
  attr :detail, :string, default: nil

  @spec validation_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def validation_badge(assigns) do
    ~H"""
    <.badge size="xs" class={"gap-1 #{badge_class(@status)}"}>
      <span>{status_icon(@status)}</span>
      <span>{@check}</span>
      <span :if={@detail}>{@detail}</span>
    </.badge>
    """
  end

  # --- Private Components ---

  attr :name, :string, required: true
  attr :status, :atom, required: true
  attr :issues, :list, default: []

  defp check_section(assigns) do
    ~H"""
    <div class="rounded-md border p-2">
      <div class="flex items-center gap-2">
        <span class={status_text_class(@status)}>{status_icon(@status)}</span>
        <span class="text-sm font-medium">{@name}</span>
        <span :if={@issues != []} class="text-muted-caption">
          ({length(@issues)} {if length(@issues) == 1, do: "issue", else: "issues"})
        </span>
      </div>
      <div :if={@issues != []} class="mt-1 space-y-0.5">
        <div
          :for={issue <- @issues}
          class="text-muted-caption font-mono pl-5 truncate"
          title={issue}
        >
          {issue}
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :results, :list, default: []

  defp test_section(assigns) do
    # Normalize results to handle both atom and string keys (from DB JSONB)
    results =
      Enum.map(assigns.results, fn r ->
        %{
          status: r[:status] || r["status"],
          name: r[:name] || r["name"],
          error: r[:error] || r["error"]
        }
      end)

    passed = Enum.count(results, &(&1.status == "passed"))
    total = length(results)
    assigns = assign(assigns, passed: passed, total: total, results: results)

    ~H"""
    <div class="rounded-md border p-2">
      <div class="flex items-center gap-2">
        <span class={status_text_class(@status)}>{status_icon(@status)}</span>
        <span class="text-sm font-medium">Tests</span>
        <span :if={@status == :skipped} class="text-muted-caption">(skipped)</span>
        <span
          :if={@status != :skipped}
          class={[
            "text-xs font-semibold",
            if(@passed == @total, do: "text-success-foreground", else: "text-destructive")
          ]}
        >
          {@passed}/{@total} passing
        </span>
      </div>
      <div :if={@results != []} class="mt-1 space-y-0.5">
        <div :for={result <- @results} class="flex items-center gap-1 text-xs pl-5">
          <span :if={result.status == "passed"} class="text-success-foreground">✓</span>
          <span :if={result.status == "failed"} class="text-destructive">✗</span>
          <span class="truncate text-muted-foreground" title={result.name}>{result.name}</span>
          <span :if={result.error} class="text-destructive truncate" title={result.error}>
            — {result.error}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp status_icon(:pass), do: "✓"
  defp status_icon(:fail), do: "✗"
  defp status_icon(:skipped), do: "—"
  defp status_icon(:warn), do: "⚠"
  defp status_icon(_), do: "○"

  defp status_text_class(:pass), do: "text-success-foreground"
  defp status_text_class(:fail), do: "text-destructive"
  defp status_text_class(:skipped), do: "text-muted-foreground"
  defp status_text_class(_), do: "text-warning-foreground"

  defp badge_class(status), do: result_classes(status)
end
