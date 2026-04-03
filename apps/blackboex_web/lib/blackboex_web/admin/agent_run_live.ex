defmodule BlackboexWeb.Admin.AgentRunLive do
  @moduledoc """
  Backpex LiveResource for viewing agent runs in the admin panel.
  Read-only.
  """

  alias Blackboex.Conversations.Run

  use Backpex.LiveResource,
    adapter_config: [
      schema: Run,
      repo: Blackboex.Repo,
      update_changeset: &Run.admin_changeset/3,
      create_changeset: &Run.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Agent Run"

  @impl Backpex.LiveResource
  def plural_name, do: "Agent Runs"

  @impl Backpex.LiveResource
  def fields do
    [
      run_type: %{
        module: Backpex.Fields.Text,
        label: "Type",
        searchable: true
      },
      status: %{
        module: Backpex.Fields.Text,
        label: "Status",
        searchable: true
      },
      trigger_message: %{
        module: Backpex.Fields.Text,
        label: "Trigger",
        only: [:index, :show]
      },
      model: %{
        module: Backpex.Fields.Text,
        label: "Model",
        only: [:show]
      },
      iteration_count: %{
        module: Backpex.Fields.Number,
        label: "Iterations"
      },
      event_count: %{
        module: Backpex.Fields.Number,
        label: "Events"
      },
      input_tokens: %{
        module: Backpex.Fields.Number,
        label: "Input Tokens",
        only: [:show]
      },
      output_tokens: %{
        module: Backpex.Fields.Number,
        label: "Output Tokens",
        only: [:show]
      },
      cost_cents: %{
        module: Backpex.Fields.Number,
        label: "Cost (cents)"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      final_code: %{
        module: Backpex.Fields.Textarea,
        label: "Final Code",
        only: [:show]
      },
      error_summary: %{
        module: Backpex.Fields.Text,
        label: "Error",
        only: [:show]
      },
      run_summary: %{
        module: Backpex.Fields.Text,
        label: "Summary",
        only: [:show]
      },
      conversation_id: %{
        module: Backpex.Fields.Text,
        label: "Conversation ID"
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
