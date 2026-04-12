defmodule BlackboexWeb.Showcase.Sections.ValidationDashboard do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.ValidationDashboard

  @code_loading ~S"""
  <.validation_dashboard loading={true} />
  """

  @code_nil ~S"""
  <.validation_dashboard report={nil} />
  """

  @code_badges ~S"""
  <div class="flex flex-wrap gap-2">
    <.validation_badge check="Compilation" status={:pass} />
    <.validation_badge check="Format" status={:fail} />
    <.validation_badge check="Credo" status={:warn} />
    <.validation_badge check="Tests" status={:skipped} />
  </div>
  """

  @code_full ~S"""
  <.validation_dashboard report={%{
    overall: :pass,
    compilation: :pass,
    compilation_errors: [],
    format: :pass,
    format_issues: [],
    credo: :warn,
    credo_issues: ["lib/handler.ex:12: Credo.Check.Readability.ModuleDoc"],
    tests: :pass,
    test_results: [
      %{status: "passed", name: "PaymentsTest: processes valid payment", error: nil},
      %{status: "passed", name: "PaymentsTest: rejects invalid amount", error: nil}
    ]
  }} />
  """

  @code_badges_list ~S"""
  <div class="space-y-1">
    <div class="flex items-center gap-2">
      <.validation_badge check="Compilation" status={:pass} />
      <span class="text-xs text-muted-foreground">No errors found</span>
    </div>
    <div class="flex items-center gap-2">
      <.validation_badge check="Format" status={:fail} detail="3 files" />
      <span class="text-xs text-muted-foreground">Unformatted files</span>
    </div>
    <div class="flex items-center gap-2">
      <.validation_badge check="Credo" status={:warn} detail="1 issue" />
      <span class="text-xs text-muted-foreground">Design warning</span>
    </div>
    <div class="flex items-center gap-2">
      <.validation_badge check="Tests" status={:skipped} />
      <span class="text-xs text-muted-foreground">No test file generated</span>
    </div>
  </div>
  """

  @full_report %{
    overall: :pass,
    compilation: :pass,
    compilation_errors: [],
    format: :pass,
    format_issues: [],
    credo: :warn,
    credo_issues: ["lib/handler.ex:12: Credo.Check.Readability.ModuleDoc"],
    tests: :pass,
    test_results: [
      %{status: "passed", name: "PaymentsTest: processes valid payment", error: nil},
      %{status: "passed", name: "PaymentsTest: rejects invalid amount", error: nil}
    ]
  }

  @fail_report %{
    overall: :fail,
    compilation: :fail,
    compilation_errors: ["lib/handler.ex:5: undefined function handle/1"],
    format: :fail,
    format_issues: ["lib/handler.ex", "lib/request.ex"],
    credo: :fail,
    credo_issues: ["lib/handler.ex:12: Credo.Check.Readability.ModuleDoc"],
    tests: :skipped,
    test_results: []
  }

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_loading, @code_loading)
      |> assign(:code_nil, @code_nil)
      |> assign(:code_badges, @code_badges)
      |> assign(:code_full, @code_full)
      |> assign(:code_badges_list, @code_badges_list)
      |> assign(:full_report, @full_report)
      |> assign(:fail_report, @fail_report)

    ~H"""
    <.section_header
      title="ValidationDashboard"
      description="Validation results dashboard for API code quality checks. validation_dashboard renders the full check results panel from a report map; validation_badge renders an individual check result (used by validation_dashboard internally but also composable standalone)."
      module="BlackboexWeb.Components.Editor.ValidationDashboard"
    />
    <div class="space-y-10">
      <.showcase_block title="Loading state" code={@code_loading}>
        <.validation_dashboard loading={true} />
      </.showcase_block>

      <.showcase_block title="No report (empty)" code={@code_nil}>
        <p class="text-sm text-muted-foreground italic">
          Pass <code class="bg-muted px-1 py-0.5 rounded text-xs">loading={true}</code>
          while fetching,
          or omit the report entirely. The component expects a map; use the loading state to cover
          the nil/pending case.
        </p>
      </.showcase_block>

      <.showcase_block title="ValidationBadge variants" code={@code_badges}>
        <div class="flex flex-wrap gap-2">
          <.validation_badge check="Compilation" status={:pass} />
          <.validation_badge check="Format" status={:fail} />
          <.validation_badge check="Credo" status={:warn} />
          <.validation_badge check="Tests" status={:skipped} />
        </div>
      </.showcase_block>

      <.showcase_block title="Full report — all pass" code={@code_full}>
        <.validation_dashboard report={@full_report} />
      </.showcase_block>

      <.showcase_block title="Full report — with failures">
        <.validation_dashboard report={@fail_report} />
      </.showcase_block>

      <.showcase_block title="Individual badges in a list" code={@code_badges_list}>
        <div class="space-y-1">
          <div class="flex items-center gap-2">
            <.validation_badge check="Compilation" status={:pass} />
            <span class="text-xs text-muted-foreground">No errors found</span>
          </div>
          <div class="flex items-center gap-2">
            <.validation_badge check="Format" status={:fail} detail="3 files" />
            <span class="text-xs text-muted-foreground">Unformatted files</span>
          </div>
          <div class="flex items-center gap-2">
            <.validation_badge check="Credo" status={:warn} detail="1 issue" />
            <span class="text-xs text-muted-foreground">Design warning</span>
          </div>
          <div class="flex items-center gap-2">
            <.validation_badge check="Tests" status={:skipped} />
            <span class="text-xs text-muted-foreground">No test file generated</span>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
