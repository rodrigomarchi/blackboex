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
        label: "Test Code"
      },
      results: %{
        module: Backpex.Fields.Text,
        label: "Results",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :results)

          text =
            if is_map(value) or is_list(value),
              do: inspect(value, pretty: true, limit: :infinity),
              else: to_string(value || "")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
          """
        end
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
