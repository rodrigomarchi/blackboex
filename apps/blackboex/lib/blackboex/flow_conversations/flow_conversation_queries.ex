defmodule Blackboex.FlowConversations.FlowConversationQueries do
  @moduledoc """
  Composable query builders for `FlowConversation`, `FlowRun`, and `FlowEvent`
  schemas. Pure query construction — no `Repo.*` calls.
  """

  import Ecto.Query, warn: false

  alias Blackboex.FlowConversations.{FlowConversation, FlowEvent, FlowRun}

  @spec increment_stats(String.t()) :: Ecto.Query.t()
  def increment_stats(conversation_id) do
    from(c in FlowConversation, where: c.id == ^conversation_id)
  end

  @spec runs_for_conversation(String.t(), pos_integer()) :: Ecto.Query.t()
  def runs_for_conversation(conversation_id, limit) do
    from(r in FlowRun,
      where: r.conversation_id == ^conversation_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
  end

  @spec recent_events_for_flow(String.t(), pos_integer()) :: Ecto.Query.t()
  def recent_events_for_flow(flow_id, limit) do
    from(e in FlowEvent,
      join: r in FlowRun,
      on: e.run_id == r.id,
      where: r.flow_id == ^flow_id,
      order_by: [asc: r.inserted_at, asc: e.sequence],
      limit: ^limit
    )
  end

  @spec events_for_run(String.t(), pos_integer()) :: Ecto.Query.t()
  def events_for_run(run_id, limit) do
    from(e in FlowEvent,
      where: e.run_id == ^run_id,
      order_by: [asc: e.sequence],
      limit: ^limit
    )
  end

  @spec events_for_conversation(String.t(), pos_integer()) :: Ecto.Query.t()
  def events_for_conversation(conversation_id, limit) do
    from(e in FlowEvent,
      join: r in FlowRun,
      on: e.run_id == r.id,
      where: r.conversation_id == ^conversation_id,
      order_by: [asc: r.inserted_at, asc: e.sequence],
      limit: ^limit
    )
  end

  @spec event_count(String.t()) :: Ecto.Query.t()
  def event_count(run_id) do
    from(e in FlowEvent,
      where: e.run_id == ^run_id,
      select: count(e.id)
    )
  end
end
