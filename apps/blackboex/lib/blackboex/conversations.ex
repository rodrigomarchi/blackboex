defmodule Blackboex.Conversations do
  @moduledoc """
  Context for managing agent conversations, runs, and events.

  Conversations are the top-level container (1:1 with an API).
  Runs represent individual agent executions within a conversation.
  Events are atomic actions persisted for full observability and analysis.
  """

  import Ecto.Query

  alias Blackboex.Conversations.{Conversation, Event, Run}
  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_conversation(String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_conversation(api_id, organization_id) do
    case Repo.get_by(Conversation, api_id: api_id) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{api_id: api_id, organization_id: organization_id})
        |> Repo.insert()

      conversation ->
        {:ok, conversation}
    end
  end

  @spec get_conversation(String.t()) :: Conversation.t() | nil
  def get_conversation(id), do: Repo.get(Conversation, id)

  @spec get_conversation_by_api(String.t()) :: Conversation.t() | nil
  def get_conversation_by_api(api_id), do: Repo.get_by(Conversation, api_id: api_id)

  @spec update_conversation_stats(Conversation.t(), map()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def update_conversation_stats(conversation, attrs) do
    conversation
    |> Conversation.stats_changeset(attrs)
    |> Repo.update()
  end

  @spec increment_conversation_stats(Conversation.t(), keyword()) ::
          {non_neg_integer(), nil}
  def increment_conversation_stats(%Conversation{id: id}, increments) do
    from(c in Conversation, where: c.id == ^id)
    |> Repo.update_all(inc: increments)
  end

  # ── Runs ───────────────────────────────────────────────────────

  @spec create_run(map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: Run.t() | nil
  def get_run(id), do: Repo.get(Run, id)

  @spec get_run!(String.t()) :: Run.t()
  def get_run!(id), do: Repo.get!(Run, id)

  @spec complete_run(Run.t(), map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def complete_run(run, attrs) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    run
    |> Run.completion_changeset(Map.merge(attrs, %{completed_at: now, duration_ms: duration}))
    |> Repo.update()
  end

  @spec update_run_metrics(Run.t(), map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def update_run_metrics(run, attrs) do
    run
    |> Run.metrics_changeset(attrs)
    |> Repo.update()
  end

  @spec list_runs(String.t(), keyword()) :: [Run.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(r in Run,
      where: r.conversation_id == ^conversation_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec list_stale_runs(non_neg_integer()) :: [Run.t()]
  def list_stale_runs(stale_after_ms \\ 120_000) do
    cutoff = DateTime.add(DateTime.utc_now(), -stale_after_ms, :millisecond)

    from(r in Run,
      where: r.status == "running",
      where: r.updated_at < ^cutoff
    )
    |> Repo.all()
  end

  # ── Events ─────────────────────────────────────────────────────

  @spec append_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(String.t(), keyword()) :: [Event.t()]
  def list_events(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    from(e in Event,
      where: e.run_id == ^run_id,
      order_by: [asc: e.sequence],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec next_sequence(String.t()) :: non_neg_integer()
  def next_sequence(run_id) do
    from(e in Event,
      where: e.run_id == ^run_id,
      select: count(e.id)
    )
    |> Repo.one()
  end

  @spec count_tool_calls(String.t(), String.t()) :: non_neg_integer()
  def count_tool_calls(run_id, tool_name) do
    from(e in Event,
      where: e.run_id == ^run_id,
      where: e.event_type == "tool_call",
      where: e.tool_name == ^tool_name
    )
    |> Repo.aggregate(:count)
  end

  @spec recent_tool_calls(String.t(), non_neg_integer()) :: [Event.t()]
  def recent_tool_calls(run_id, count \\ 3) do
    from(e in Event,
      where: e.run_id == ^run_id,
      where: e.event_type == "tool_call",
      order_by: [desc: e.sequence],
      limit: ^count
    )
    |> Repo.all()
  end

  @spec run_summary_for_context(String.t(), non_neg_integer()) :: [map()]
  def run_summary_for_context(conversation_id, limit \\ 5) do
    from(r in Run,
      where: r.conversation_id == ^conversation_id,
      where: r.status in ["completed", "partial"],
      order_by: [desc: r.inserted_at],
      limit: ^limit,
      select: %{
        run_type: r.run_type,
        trigger_message: r.trigger_message,
        run_summary: r.run_summary,
        status: r.status
      }
    )
    |> Repo.all()
    |> Enum.reverse()
  end
end
