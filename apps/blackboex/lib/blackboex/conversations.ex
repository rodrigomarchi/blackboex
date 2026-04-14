defmodule Blackboex.Conversations do
  @moduledoc """
  Context for managing agent conversations, runs, and events.

  Conversations are the top-level container (1:1 with an API).
  Runs represent individual agent executions within a conversation.
  Events are atomic actions persisted for full observability and analysis.
  """

  alias Blackboex.Conversations.{Conversation, ConversationQueries, Event, Run}
  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_conversation(String.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_conversation(api_id, organization_id, project_id) do
    case Repo.get_by(Conversation, api_id: api_id) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{
          api_id: api_id,
          organization_id: organization_id,
          project_id: project_id
        })
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
    id
    |> ConversationQueries.increment_stats()
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

  @spec touch_run(String.t()) :: :ok
  def touch_run(run_id) do
    run_id
    |> ConversationQueries.touch_run()
    |> Repo.update_all(set: [updated_at: DateTime.utc_now()])

    :ok
  end

  @spec list_runs(String.t(), keyword()) :: [Run.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversation_id
    |> ConversationQueries.runs_for_conversation(limit)
    |> Repo.all()
  end

  @spec list_stale_runs(non_neg_integer()) :: [Run.t()]
  def list_stale_runs(stale_after_ms \\ 120_000) do
    cutoff = DateTime.add(DateTime.utc_now(), -stale_after_ms, :millisecond)

    cutoff
    |> ConversationQueries.stale_runs()
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

    run_id
    |> ConversationQueries.events_for_run(limit)
    |> Repo.all()
  end

  @spec next_sequence(String.t()) :: non_neg_integer()
  def next_sequence(run_id) do
    run_id
    |> ConversationQueries.event_count()
    |> Repo.one()
  end
end
