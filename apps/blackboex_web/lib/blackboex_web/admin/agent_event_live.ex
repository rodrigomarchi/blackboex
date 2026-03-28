defmodule BlackboexWeb.Admin.AgentEventLive do
  @moduledoc """
  Backpex LiveResource for viewing agent events in the admin panel.
  Read-only. Note: Event uses `inserted_at` only (no `updated_at`).
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Conversations.Event,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Conversations.Event.admin_changeset/3,
      create_changeset: &Blackboex.Conversations.Event.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Agent Event"

  @impl Backpex.LiveResource
  def plural_name, do: "Agent Events"

  @impl Backpex.LiveResource
  def fields do
    [
      event_type: %{
        module: Backpex.Fields.Text,
        label: "Type",
        searchable: true
      },
      sequence: %{
        module: Backpex.Fields.Number,
        label: "Seq"
      },
      role: %{
        module: Backpex.Fields.Text,
        label: "Role"
      },
      content: %{
        module: Backpex.Fields.Textarea,
        label: "Content",
        only: [:show]
      },
      tool_name: %{
        module: Backpex.Fields.Text,
        label: "Tool",
        searchable: true
      },
      tool_success: %{
        module: Backpex.Fields.Boolean,
        label: "Success"
      },
      tool_duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)",
        only: [:show]
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
      run_id: %{
        module: Backpex.Fields.Text,
        label: "Run ID"
      },
      conversation_id: %{
        module: Backpex.Fields.Text,
        label: "Conversation ID"
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
