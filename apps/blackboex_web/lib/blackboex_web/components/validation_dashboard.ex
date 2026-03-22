defmodule BlackboexWeb.Components.ValidationDashboard do
  @moduledoc """
  Dashboard component showing results of all validation checks:
  compilation, format, Credo, and tests.
  """

  use BlackboexWeb, :html

  attr :report, :map, default: nil
  attr :loading, :boolean, default: false

  @spec validation_dashboard(map()) :: Phoenix.LiveView.Rendered.t()
  def validation_dashboard(assigns) do
    ~H"""
    <div :if={@loading} class="flex items-center gap-2 text-sm text-muted-foreground p-4">
      <.icon name="hero-arrow-path" class="size-4 animate-spin" />
      <span>Running validations...</span>
    </div>

    <div :if={!@loading && @report == nil} class="p-4 text-sm text-muted-foreground">
      No validation results yet. Save to run validations.
    </div>

    <div :if={!@loading && @report != nil} class="space-y-3 p-3">
      <%!-- Overall badge --%>
      <div class="flex items-center gap-2">
        <span class={[
          "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
          if(@report.overall == :pass,
            do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
            else: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
          )
        ]}>
          {if @report.overall == :pass, do: "ALL PASS", else: "ISSUES FOUND"}
        </span>
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
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold",
      badge_class(@status)
    ]}>
      <span>{status_icon(@status)}</span>
      <span>{@check}</span>
      <span :if={@detail}>{@detail}</span>
    </span>
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
        <span :if={@issues != []} class="text-xs text-muted-foreground">
          ({length(@issues)} {if length(@issues) == 1, do: "issue", else: "issues"})
        </span>
      </div>
      <div :if={@issues != []} class="mt-1 space-y-0.5">
        <div
          :for={issue <- @issues}
          class="text-xs text-muted-foreground font-mono pl-5 truncate"
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
    passed = Enum.count(assigns.results, &(&1.status == "passed"))
    total = length(assigns.results)
    assigns = assign(assigns, passed: passed, total: total)

    ~H"""
    <div class="rounded-md border p-2">
      <div class="flex items-center gap-2">
        <span class={status_text_class(@status)}>{status_icon(@status)}</span>
        <span class="text-sm font-medium">Tests</span>
        <span :if={@status == :skipped} class="text-xs text-muted-foreground">(skipped)</span>
        <span
          :if={@status != :skipped}
          class={[
            "text-xs font-semibold",
            if(@passed == @total, do: "text-green-600", else: "text-red-600")
          ]}
        >
          {@passed}/{@total} passing
        </span>
      </div>
      <div :if={@results != []} class="mt-1 space-y-0.5">
        <div :for={result <- @results} class="flex items-center gap-1 text-xs pl-5">
          <span :if={result.status == "passed"} class="text-green-600">✓</span>
          <span :if={result.status == "failed"} class="text-red-600">✗</span>
          <span class="truncate text-muted-foreground" title={result.name}>{result.name}</span>
          <span :if={result.error} class="text-red-500 truncate" title={result.error}>
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

  defp status_text_class(:pass), do: "text-green-600"
  defp status_text_class(:fail), do: "text-red-600"
  defp status_text_class(:skipped), do: "text-muted-foreground"
  defp status_text_class(_), do: "text-yellow-600"

  defp badge_class(:pass), do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
  defp badge_class(:fail), do: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300"

  defp badge_class(:skipped),
    do: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400"

  defp badge_class(_), do: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
end
