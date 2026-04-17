defmodule Blackboex.PlaygroundConversations do
  @moduledoc """
  Context for managing AI chat conversations inside Playgrounds.

  A conversation is the top-level container (1:1 with a Playground). Runs
  represent individual AI agent executions (`generate` or `edit`). Events are
  atomic messages or code deltas within a run, persisted for observability and
  to hydrate the chat timeline when a LiveView reconnects.

  Intentionally separate from `Blackboex.Conversations` (1:1 with API) so the
  two domains stay isolated and evolve independently.
  """

  alias Blackboex.PlaygroundConversations.{
    PlaygroundConversation,
    PlaygroundConversationQueries,
    PlaygroundEvent,
    PlaygroundRun
  }

  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_active_conversation(String.t(), String.t(), String.t()) ::
          {:ok, PlaygroundConversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_active_conversation(playground_id, organization_id, project_id) do
    case Repo.get_by(PlaygroundConversation, playground_id: playground_id, status: "active") do
      nil ->
        %PlaygroundConversation{}
        |> PlaygroundConversation.changeset(%{
          playground_id: playground_id,
          organization_id: organization_id,
          project_id: project_id,
          status: "active"
        })
        |> Repo.insert()

      conversation ->
        {:ok, conversation}
    end
  end

  @doc """
  Archives the currently active conversation (if any) for the given playground
  and creates a fresh active conversation. Used by the "New chat" action in
  the UI to start a new thread without losing history.
  """
  @spec start_new_conversation(String.t(), String.t(), String.t()) ::
          {:ok, PlaygroundConversation.t()} | {:error, Ecto.Changeset.t()}
  def start_new_conversation(playground_id, organization_id, project_id) do
    _ = archive_active_conversation(playground_id)

    %PlaygroundConversation{}
    |> PlaygroundConversation.changeset(%{
      playground_id: playground_id,
      organization_id: organization_id,
      project_id: project_id,
      status: "active"
    })
    |> Repo.insert()
  end

  @spec archive_active_conversation(String.t()) ::
          {:ok, PlaygroundConversation.t()} | :noop | {:error, Ecto.Changeset.t()}
  def archive_active_conversation(playground_id) do
    case Repo.get_by(PlaygroundConversation, playground_id: playground_id, status: "active") do
      nil ->
        :noop

      conversation ->
        conversation
        |> PlaygroundConversation.archive_changeset()
        |> Repo.update()
    end
  end

  @spec get_conversation(String.t()) :: PlaygroundConversation.t() | nil
  def get_conversation(id), do: Repo.get(PlaygroundConversation, id)

  @spec get_active_conversation(String.t()) :: PlaygroundConversation.t() | nil
  def get_active_conversation(playground_id) do
    Repo.get_by(PlaygroundConversation, playground_id: playground_id, status: "active")
  end

  @spec increment_conversation_stats(PlaygroundConversation.t(), keyword()) ::
          {non_neg_integer(), nil}
  def increment_conversation_stats(%PlaygroundConversation{id: id}, increments) do
    id
    |> PlaygroundConversationQueries.increment_stats()
    |> Repo.update_all(inc: increments)
  end

  # ── Runs ───────────────────────────────────────────────────────

  @spec create_run(map()) :: {:ok, PlaygroundRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) do
    %PlaygroundRun{}
    |> PlaygroundRun.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: PlaygroundRun.t() | nil
  def get_run(id), do: Repo.get(PlaygroundRun, id)

  @spec get_run!(String.t()) :: PlaygroundRun.t()
  def get_run!(id), do: Repo.get!(PlaygroundRun, id)

  @spec mark_run_running(PlaygroundRun.t()) ::
          {:ok, PlaygroundRun.t()} | {:error, Ecto.Changeset.t()}
  def mark_run_running(run) do
    run
    |> PlaygroundRun.running_changeset(%{
      status: "running",
      started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @spec complete_run(PlaygroundRun.t(), map()) ::
          {:ok, PlaygroundRun.t()} | {:error, Ecto.Changeset.t()}
  def complete_run(run, attrs) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    merged =
      attrs
      |> Map.put_new(:status, "completed")
      |> Map.merge(%{completed_at: now, duration_ms: duration})

    run
    |> PlaygroundRun.completion_changeset(merged)
    |> Repo.update()
  end

  @spec fail_run(PlaygroundRun.t(), String.t()) ::
          {:ok, PlaygroundRun.t()} | {:error, Ecto.Changeset.t()}
  def fail_run(run, reason) when is_binary(reason) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    run
    |> PlaygroundRun.completion_changeset(%{
      status: "failed",
      error_message: reason,
      completed_at: now,
      duration_ms: duration
    })
    |> Repo.update()
  end

  @spec list_runs(String.t(), keyword()) :: [PlaygroundRun.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversation_id
    |> PlaygroundConversationQueries.runs_for_conversation(limit)
    |> Repo.all()
  end

  # ── Events ─────────────────────────────────────────────────────

  @spec append_event(PlaygroundRun.t(), map()) ::
          {:ok, PlaygroundEvent.t()} | {:error, Ecto.Changeset.t()}
  def append_event(%PlaygroundRun{id: run_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:sequence, fn -> next_sequence(run_id) end)
      |> Map.put(:run_id, run_id)

    %PlaygroundEvent{}
    |> PlaygroundEvent.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(String.t(), keyword()) :: [PlaygroundEvent.t()]
  def list_events(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    run_id
    |> PlaygroundConversationQueries.events_for_run(limit)
    |> Repo.all()
  end

  @spec list_recent_events_for_playground(String.t(), keyword()) :: [PlaygroundEvent.t()]
  def list_recent_events_for_playground(playground_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    playground_id
    |> PlaygroundConversationQueries.recent_events_for_playground(limit)
    |> Repo.all()
  end

  @doc """
  Returns events for the ACTIVE conversation of a playground — what the chat
  UI should show and what the LLM sees as thread history. Events from older,
  archived conversations are excluded.
  """
  @spec list_active_conversation_events(String.t(), keyword()) :: [PlaygroundEvent.t()]
  def list_active_conversation_events(playground_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    case get_active_conversation(playground_id) do
      nil ->
        []

      conversation ->
        conversation.id
        |> PlaygroundConversationQueries.events_for_conversation(limit)
        |> Repo.all()
    end
  end

  @doc """
  Returns the thread history (user/assistant message pairs) for the currently
  active conversation of a playground, as `[%{role, content}]` tuples ordered
  oldest-first. Used to inject context into the LLM prompt so the agent
  behaves like a true thread instead of a one-shot.
  """
  @spec thread_history(String.t(), keyword()) :: [%{role: String.t(), content: String.t()}]
  def thread_history(playground_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    playground_id
    |> list_active_conversation_events(limit: limit * 2)
    |> Enum.flat_map(&event_to_history_message/1)
    |> Enum.take(-limit)
  end

  defp event_to_history_message(%{event_type: "user_message", content: content})
       when is_binary(content),
       do: [%{role: "user", content: content}]

  defp event_to_history_message(%{event_type: "completed", content: content})
       when is_binary(content),
       do: [%{role: "assistant", content: content}]

  defp event_to_history_message(_), do: []

  @spec next_sequence(String.t()) :: non_neg_integer()
  def next_sequence(run_id) do
    run_id
    |> PlaygroundConversationQueries.event_count()
    |> Repo.one() || 0
  end
end
