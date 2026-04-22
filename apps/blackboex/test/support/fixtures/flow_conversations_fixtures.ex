defmodule Blackboex.FlowConversationsFixtures do
  @moduledoc """
  Test helpers for creating FlowConversation, FlowRun, and FlowEvent entities.
  """

  alias Blackboex.FlowConversations
  alias Blackboex.FlowConversations.FlowConversation
  alias Blackboex.FlowConversations.FlowEvent
  alias Blackboex.FlowConversations.FlowRun
  alias Blackboex.Repo

  @doc """
  Gets or creates a FlowConversation.

  ## Options

    * `:flow` - the Flow (required, or auto-created with user/org)
    * `:user`, `:org`, `:project` - passed through when auto-creating the flow

  Returns the FlowConversation struct.
  """
  @spec flow_conversation_fixture(map()) :: FlowConversation.t()
  def flow_conversation_fixture(attrs \\ %{}) do
    flow =
      attrs[:flow] ||
        Blackboex.FlowsFixtures.flow_fixture(Map.take(attrs, [:user, :org, :project]))

    {:ok, conversation} =
      FlowConversations.get_or_create_active_conversation(
        flow.id,
        flow.organization_id,
        flow.project_id
      )

    conversation
  end

  @doc """
  Creates a FlowRun.

  ## Options

    * `:conversation` - the parent FlowConversation (required, or auto-created)
    * `:flow` - flow forwarded to auto-conversation creation
    * `:user` - the owning user (required, or auto-created)
    * `:run_type` - default `"edit"`
    * `:status` - default `"pending"`
    * `:trigger_message`, `:definition_before` - passed through

  Returns the FlowRun struct.
  """
  @spec flow_run_fixture(map()) :: FlowRun.t()
  def flow_run_fixture(attrs \\ %{}) do
    conversation =
      attrs[:conversation] ||
        flow_conversation_fixture(Map.take(attrs, [:flow, :user, :org, :project]))

    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()

    known_keys = [:conversation, :flow, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    {:ok, run} =
      FlowConversations.create_run(
        Map.merge(
          %{
            conversation_id: conversation.id,
            flow_id: conversation.flow_id,
            organization_id: conversation.organization_id,
            user_id: user.id,
            run_type: "edit",
            status: "pending",
            trigger_message: "adicione um delay de 2s",
            definition_before: %{}
          },
          extra
        )
      )

    run
  end

  @doc """
  Creates a FlowEvent. Requires `:run` or passes `:run_id` through.
  Auto-assigns the next sequence if not provided.
  """
  @spec flow_event_fixture(map()) :: FlowEvent.t()
  def flow_event_fixture(attrs \\ %{}) do
    run =
      attrs[:run] ||
        flow_run_fixture(Map.take(attrs, [:conversation, :flow, :user, :org, :project]))

    known_keys = [:run, :conversation, :flow, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    sequence = Map.get(extra, :sequence, FlowConversations.next_sequence(run.id))

    attrs_with_defaults =
      Map.merge(
        %{
          run_id: run.id,
          sequence: sequence,
          event_type: "user_message",
          content: "oi",
          metadata: %{}
        },
        Map.drop(extra, [:sequence])
      )
      |> Map.put(:sequence, sequence)

    {:ok, event} =
      %FlowEvent{}
      |> FlowEvent.changeset(attrs_with_defaults)
      |> Repo.insert()

    event
  end
end
