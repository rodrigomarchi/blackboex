defmodule Blackboex.Conversations.ConversationQueries do
  @moduledoc """
  Composable query builders for Conversation, Run, and Event schemas.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Conversations.{Conversation, Event, Run}

  # ── Conversations ──────────────────────────────────────────

  @spec increment_stats(String.t()) :: Ecto.Query.t()
  def increment_stats(conversation_id) do
    from(c in Conversation, where: c.id == ^conversation_id)
  end

  # ── Runs ───────────────────────────────────────────────────

  @spec runs_for_conversation(String.t(), pos_integer()) :: Ecto.Query.t()
  def runs_for_conversation(conversation_id, limit) do
    from(r in Run,
      where: r.conversation_id == ^conversation_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
  end

  @spec stale_runs(DateTime.t()) :: Ecto.Query.t()
  def stale_runs(cutoff) do
    from(r in Run,
      where: r.status == "running",
      where: r.updated_at < ^cutoff
    )
  end

  @spec touch_run(String.t()) :: Ecto.Query.t()
  def touch_run(run_id) do
    from(r in Run, where: r.id == ^run_id)
  end

  # ── Events ─────────────────────────────────────────────────

  @spec events_for_run(String.t(), pos_integer()) :: Ecto.Query.t()
  def events_for_run(run_id, limit) do
    from(e in Event,
      where: e.run_id == ^run_id,
      order_by: [asc: e.sequence],
      limit: ^limit
    )
  end

  @spec event_count(String.t()) :: Ecto.Query.t()
  def event_count(run_id) do
    from(e in Event,
      where: e.run_id == ^run_id,
      select: count(e.id)
    )
  end
end
