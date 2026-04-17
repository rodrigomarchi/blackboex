defmodule Blackboex.PlaygroundConversations.PlaygroundConversationQueries do
  @moduledoc """
  Composable query builders for `PlaygroundConversation`, `PlaygroundRun`, and
  `PlaygroundEvent` schemas. Pure query construction — no `Repo.*` calls.
  """

  import Ecto.Query, warn: false

  alias Blackboex.PlaygroundConversations.{PlaygroundConversation, PlaygroundEvent, PlaygroundRun}

  @spec increment_stats(String.t()) :: Ecto.Query.t()
  def increment_stats(conversation_id) do
    from(c in PlaygroundConversation, where: c.id == ^conversation_id)
  end

  @spec runs_for_conversation(String.t(), pos_integer()) :: Ecto.Query.t()
  def runs_for_conversation(conversation_id, limit) do
    from(r in PlaygroundRun,
      where: r.conversation_id == ^conversation_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
  end

  @spec recent_events_for_playground(String.t(), pos_integer()) :: Ecto.Query.t()
  def recent_events_for_playground(playground_id, limit) do
    from(e in PlaygroundEvent,
      join: r in PlaygroundRun,
      on: e.run_id == r.id,
      where: r.playground_id == ^playground_id,
      order_by: [asc: r.inserted_at, asc: e.sequence],
      limit: ^limit
    )
  end

  @spec events_for_run(String.t(), pos_integer()) :: Ecto.Query.t()
  def events_for_run(run_id, limit) do
    from(e in PlaygroundEvent,
      where: e.run_id == ^run_id,
      order_by: [asc: e.sequence],
      limit: ^limit
    )
  end

  @spec events_for_conversation(String.t(), pos_integer()) :: Ecto.Query.t()
  def events_for_conversation(conversation_id, limit) do
    from(e in PlaygroundEvent,
      join: r in PlaygroundRun,
      on: e.run_id == r.id,
      where: r.conversation_id == ^conversation_id,
      order_by: [asc: r.inserted_at, asc: e.sequence],
      limit: ^limit
    )
  end

  @spec event_count(String.t()) :: Ecto.Query.t()
  def event_count(run_id) do
    from(e in PlaygroundEvent,
      where: e.run_id == ^run_id,
      select: count(e.id)
    )
  end
end
