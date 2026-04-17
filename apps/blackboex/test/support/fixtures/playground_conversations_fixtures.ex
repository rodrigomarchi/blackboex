defmodule Blackboex.PlaygroundConversationsFixtures do
  @moduledoc """
  Test helpers for creating PlaygroundConversation, PlaygroundRun, and
  PlaygroundEvent entities.
  """

  alias Blackboex.PlaygroundConversations
  alias Blackboex.PlaygroundConversations.PlaygroundConversation
  alias Blackboex.PlaygroundConversations.PlaygroundEvent
  alias Blackboex.PlaygroundConversations.PlaygroundRun
  alias Blackboex.Repo

  @doc """
  Gets or creates a PlaygroundConversation.

  ## Options

    * `:playground` - the Playground (required, or auto-created with user/org)
    * `:user`, `:org`, `:project` - passed through when auto-creating the playground

  Returns the PlaygroundConversation struct.
  """
  @spec playground_conversation_fixture(map()) :: PlaygroundConversation.t()
  def playground_conversation_fixture(attrs \\ %{}) do
    playground =
      attrs[:playground] ||
        Blackboex.PlaygroundsFixtures.playground_fixture(Map.take(attrs, [:user, :org, :project]))

    {:ok, conversation} =
      PlaygroundConversations.get_or_create_active_conversation(
        playground.id,
        playground.organization_id,
        playground.project_id
      )

    conversation
  end

  @doc """
  Creates a PlaygroundRun.

  ## Options

    * `:conversation` - the parent PlaygroundConversation (required, or auto-created)
    * `:playground` - playground forwarded to auto-conversation creation
    * `:user` - the owning user (required, or auto-created)
    * `:run_type` - default `"edit"`
    * `:status` - default `"pending"`
    * `:trigger_message`, `:code_before` - passed through

  Returns the PlaygroundRun struct.
  """
  @spec playground_run_fixture(map()) :: PlaygroundRun.t()
  def playground_run_fixture(attrs \\ %{}) do
    conversation =
      attrs[:conversation] ||
        playground_conversation_fixture(Map.take(attrs, [:playground, :user, :org, :project]))

    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()

    known_keys = [:conversation, :playground, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    {:ok, run} =
      PlaygroundConversations.create_run(
        Map.merge(
          %{
            conversation_id: conversation.id,
            playground_id: conversation.playground_id,
            organization_id: conversation.organization_id,
            user_id: user.id,
            run_type: "edit",
            status: "pending",
            trigger_message: "make it faster",
            code_before: ""
          },
          extra
        )
      )

    run
  end

  @doc """
  Creates a PlaygroundEvent. Requires `:run` or passes `:run_id` through.
  Auto-assigns the next sequence if not provided.
  """
  @spec playground_event_fixture(map()) :: PlaygroundEvent.t()
  def playground_event_fixture(attrs \\ %{}) do
    run =
      attrs[:run] ||
        playground_run_fixture(
          Map.take(attrs, [:conversation, :playground, :user, :org, :project])
        )

    known_keys = [:run, :conversation, :playground, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    sequence = Map.get(extra, :sequence, PlaygroundConversations.next_sequence(run.id))

    attrs_with_defaults =
      Map.merge(
        %{
          run_id: run.id,
          sequence: sequence,
          event_type: "user_message",
          content: "hello",
          metadata: %{}
        },
        Map.drop(extra, [:sequence])
      )
      |> Map.put(:sequence, sequence)

    {:ok, event} =
      %PlaygroundEvent{}
      |> PlaygroundEvent.changeset(attrs_with_defaults)
      |> Repo.insert()

    event
  end
end
