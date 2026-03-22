defmodule BlackboexWeb.Admin.TestSuiteLive do
  @moduledoc """
  Backpex LiveResource for viewing test suites in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Testing.TestSuite,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Testing.TestSuite.admin_changeset/3,
      create_changeset: &Blackboex.Testing.TestSuite.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Test Suite"

  @impl Backpex.LiveResource
  def plural_name, do: "Test Suites"

  @impl Backpex.LiveResource
  def fields do
    [
      version_number: %{
        module: Backpex.Fields.Number,
        label: "Version"
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        searchable: true,
        options: [
          Pending: "pending",
          Running: "running",
          Passed: "passed",
          Failed: "failed",
          Error: "error"
        ]
      },
      total_tests: %{
        module: Backpex.Fields.Number,
        label: "Total"
      },
      passed_tests: %{
        module: Backpex.Fields.Number,
        label: "Passed"
      },
      failed_tests: %{
        module: Backpex.Fields.Number,
        label: "Failed"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      test_code: %{
        module: Backpex.Fields.Textarea,
        label: "Test Code",
        readonly: true,
        only: [:show]
      },
      results: %{
        module: Backpex.Fields.Textarea,
        label: "Results",
        readonly: true,
        only: [:show]
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true,
        only: [:show]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, :index, _item), do: platform_admin?(assigns)
  def can?(assigns, :show, _item), do: platform_admin?(assigns)
  def can?(_assigns, _action, _item), do: false

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
