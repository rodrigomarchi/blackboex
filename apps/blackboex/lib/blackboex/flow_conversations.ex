defmodule Blackboex.FlowConversations do
  @moduledoc """
  Context for managing AI chat conversations inside the Flow editor.

  A conversation is the top-level container (1 active per Flow, older threads
  archived). Runs represent individual AI agent executions (`generate` or
  `edit`). Events are atomic messages or definition deltas within a run,
  persisted for observability and to hydrate the chat timeline when a
  LiveView reconnects.

  Intentionally separate from `Blackboex.Conversations` (API),
  `Blackboex.PlaygroundConversations`, and `Blackboex.PageConversations` so
  each editor's chat evolves independently.
  """

  alias Blackboex.FlowConversations.{
    FlowConversation,
    FlowConversationQueries,
    FlowEvent,
    FlowRun
  }

  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_active_conversation(String.t(), String.t(), String.t()) ::
          {:ok, FlowConversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_active_conversation(flow_id, organization_id, project_id) do
    case Repo.get_by(FlowConversation, flow_id: flow_id, status: "active") do
      nil -> insert_or_fetch_active(flow_id, organization_id, project_id)
      conversation -> {:ok, conversation}
    end
  end

  # TOCTOU: two concurrent workers can both see nil and race to insert. The
  # partial unique index catches the loser; we then fetch the winner instead
  # of propagating the unique-constraint error back to the user.
  defp recover_from_race(changeset, flow_id) do
    if unique_flow_id_violation?(changeset.errors) do
      case Repo.get_by(FlowConversation, flow_id: flow_id, status: "active") do
        nil -> {:error, changeset}
        conv -> {:ok, conv}
      end
    else
      {:error, changeset}
    end
  end

  defp unique_flow_id_violation?(errors) do
    Enum.any?(errors, &match?({:flow_id, {_, [{:constraint, :unique} | _]}}, &1))
  end

  defp insert_or_fetch_active(flow_id, organization_id, project_id) do
    changeset =
      FlowConversation.changeset(%FlowConversation{}, %{
        flow_id: flow_id,
        organization_id: organization_id,
        project_id: project_id,
        status: "active"
      })

    case Repo.insert(changeset) do
      {:ok, conv} -> {:ok, conv}
      {:error, %Ecto.Changeset{} = changeset} -> recover_from_race(changeset, flow_id)
    end
  end

  @doc """
  Archives the currently active conversation (if any) for the given flow and
  creates a fresh active conversation. Used by the "New chat" action in the
  UI to start a new thread without losing history.
  """
  @spec start_new_conversation(String.t(), String.t(), String.t()) ::
          {:ok, FlowConversation.t()} | {:error, Ecto.Changeset.t()}
  def start_new_conversation(flow_id, organization_id, project_id) do
    _ = archive_active_conversation(flow_id)

    %FlowConversation{}
    |> FlowConversation.changeset(%{
      flow_id: flow_id,
      organization_id: organization_id,
      project_id: project_id,
      status: "active"
    })
    |> Repo.insert()
  end

  @spec archive_active_conversation(String.t()) ::
          {:ok, FlowConversation.t()} | :noop | {:error, Ecto.Changeset.t()}
  def archive_active_conversation(flow_id) do
    case Repo.get_by(FlowConversation, flow_id: flow_id, status: "active") do
      nil ->
        :noop

      conversation ->
        conversation
        |> FlowConversation.archive_changeset()
        |> Repo.update()
    end
  end

  @spec get_conversation(String.t()) :: FlowConversation.t() | nil
  def get_conversation(id), do: Repo.get(FlowConversation, id)

  @spec get_active_conversation(String.t()) :: FlowConversation.t() | nil
  def get_active_conversation(flow_id) do
    Repo.get_by(FlowConversation, flow_id: flow_id, status: "active")
  end

  @spec increment_conversation_stats(FlowConversation.t(), keyword()) ::
          {non_neg_integer(), nil}
  def increment_conversation_stats(%FlowConversation{id: id}, increments) do
    id
    |> FlowConversationQueries.increment_stats()
    |> Repo.update_all(inc: increments)
  end

  # ── Runs ───────────────────────────────────────────────────────

  @spec create_run(map()) :: {:ok, FlowRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) do
    %FlowRun{}
    |> FlowRun.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: FlowRun.t() | nil
  def get_run(id), do: Repo.get(FlowRun, id)

  @spec get_run!(String.t()) :: FlowRun.t()
  def get_run!(id), do: Repo.get!(FlowRun, id)

  @spec mark_run_running(FlowRun.t()) ::
          {:ok, FlowRun.t()} | {:error, Ecto.Changeset.t()}
  def mark_run_running(run) do
    run
    |> FlowRun.running_changeset(%{
      status: "running",
      started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @spec complete_run(FlowRun.t(), map()) ::
          {:ok, FlowRun.t()} | {:error, Ecto.Changeset.t()}
  def complete_run(run, attrs) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    merged =
      attrs
      |> Map.put_new(:status, "completed")
      |> Map.merge(%{completed_at: now, duration_ms: duration})

    run
    |> FlowRun.completion_changeset(merged)
    |> Repo.update()
  end

  @spec fail_run(FlowRun.t(), String.t()) ::
          {:ok, FlowRun.t()} | {:error, Ecto.Changeset.t()}
  def fail_run(run, reason) when is_binary(reason) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    run
    |> FlowRun.completion_changeset(%{
      status: "failed",
      error_message: reason,
      completed_at: now,
      duration_ms: duration
    })
    |> Repo.update()
  end

  @spec list_runs(String.t(), keyword()) :: [FlowRun.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversation_id
    |> FlowConversationQueries.runs_for_conversation(limit)
    |> Repo.all()
  end

  # ── Events ─────────────────────────────────────────────────────

  @spec append_event(FlowRun.t(), map()) ::
          {:ok, FlowEvent.t()} | {:error, Ecto.Changeset.t()}
  def append_event(%FlowRun{id: run_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:sequence, fn -> next_sequence(run_id) end)
      |> Map.put(:run_id, run_id)

    %FlowEvent{}
    |> FlowEvent.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(String.t(), keyword()) :: [FlowEvent.t()]
  def list_events(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    run_id
    |> FlowConversationQueries.events_for_run(limit)
    |> Repo.all()
  end

  @spec list_recent_events_for_flow(String.t(), keyword()) :: [FlowEvent.t()]
  def list_recent_events_for_flow(flow_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    flow_id
    |> FlowConversationQueries.recent_events_for_flow(limit)
    |> Repo.all()
  end

  @doc """
  Returns events for the ACTIVE conversation of a flow — what the chat UI
  should show and what the LLM sees as thread history. Events from older,
  archived conversations are excluded.
  """
  @spec list_active_conversation_events(String.t(), keyword()) :: [FlowEvent.t()]
  def list_active_conversation_events(flow_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    case get_active_conversation(flow_id) do
      nil ->
        []

      conversation ->
        conversation.id
        |> FlowConversationQueries.events_for_conversation(limit)
        |> Repo.all()
    end
  end

  @doc """
  Returns the thread history (user/assistant message pairs) for the currently
  active conversation of a flow, as `[%{role, content}]` tuples ordered
  oldest-first. Used to inject context into the LLM prompt so the agent
  behaves like a true thread instead of a one-shot.
  """
  @spec thread_history(String.t(), keyword()) :: [%{role: String.t(), content: String.t()}]
  def thread_history(flow_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    flow_id
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
    |> FlowConversationQueries.event_count()
    |> Repo.one() || 0
  end
end
