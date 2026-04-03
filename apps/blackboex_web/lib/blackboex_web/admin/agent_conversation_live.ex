defmodule BlackboexWeb.Admin.AgentConversationLive do
  @moduledoc """
  Backpex LiveResource for viewing agent conversations in the admin panel.
  Read-only.
  """

  alias Blackboex.Conversations.Conversation

  use Backpex.LiveResource,
    adapter_config: [
      schema: Conversation,
      repo: Blackboex.Repo,
      update_changeset: &Conversation.admin_changeset/3,
      create_changeset: &Conversation.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Agent Conversation"

  @impl Backpex.LiveResource
  def plural_name, do: "Agent Conversations"

  @impl Backpex.LiveResource
  def fields do
    [
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      title: %{
        module: Backpex.Fields.Text,
        label: "Title"
      },
      status: %{
        module: Backpex.Fields.Text,
        label: "Status",
        searchable: true
      },
      total_runs: %{
        module: Backpex.Fields.Number,
        label: "Total Runs"
      },
      total_events: %{
        module: Backpex.Fields.Number,
        label: "Total Events"
      },
      total_input_tokens: %{
        module: Backpex.Fields.Number,
        label: "Input Tokens",
        only: [:show]
      },
      total_output_tokens: %{
        module: Backpex.Fields.Number,
        label: "Output Tokens",
        only: [:show]
      },
      total_cost_cents: %{
        module: Backpex.Fields.Number,
        label: "Cost (cents)"
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
