defmodule Blackboex.PageConversations do
  @moduledoc """
  Context for AI chat conversations attached to a Page editor session.

  A conversation is the top-level container (one active per Page). Runs are
  individual AI passes (`generate` for empty pages, `edit` otherwise). Events
  are atomic messages or content deltas within a run, persisted so the chat
  timeline can be hydrated when the LiveView reconnects, and so the LLM can
  see prior turns as conversational history.

  Mirrors `Blackboex.PlaygroundConversations` in shape so the Page chat reuses
  the playground experience.
  """

  alias Blackboex.PageConversations.PageConversation
  alias Blackboex.PageConversations.PageConversationQueries
  alias Blackboex.PageConversations.PageEvent
  alias Blackboex.PageConversations.PageRun
  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_active_conversation(String.t(), String.t(), String.t()) ::
          {:ok, PageConversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_active_conversation(page_id, organization_id, project_id) do
    case Repo.get_by(PageConversation, page_id: page_id, status: "active") do
      nil ->
        insert_active(page_id, organization_id, project_id)

      conversation ->
        {:ok, conversation}
    end
  end

  # Race-safe insert: if two callers see `nil` from the get_by simultaneously,
  # one wins the partial unique index `(page_id) WHERE status='active'` and the
  # other gets a constraint error — at which point we re-fetch the winning row
  # so the caller never sees a spurious failure.
  defp insert_active(page_id, organization_id, project_id) do
    %PageConversation{}
    |> PageConversation.changeset(%{
      page_id: page_id,
      organization_id: organization_id,
      project_id: project_id,
      status: "active"
    })
    |> Repo.insert()
    |> recover_unique_race(page_id)
  end

  defp recover_unique_race({:ok, _} = ok, _page_id), do: ok

  defp recover_unique_race({:error, %Ecto.Changeset{errors: errors}} = err, page_id) do
    if Keyword.has_key?(errors, :page_id) do
      case Repo.get_by(PageConversation, page_id: page_id, status: "active") do
        %PageConversation{} = existing -> {:ok, existing}
        nil -> err
      end
    else
      err
    end
  end

  @doc """
  Archives the currently active conversation (if any) and creates a fresh
  active one. Used by the "New conversation" button so users can start a new
  thread without losing history.
  """
  @spec start_new_conversation(String.t(), String.t(), String.t()) ::
          {:ok, PageConversation.t()} | {:error, Ecto.Changeset.t()}
  def start_new_conversation(page_id, organization_id, project_id) do
    case archive_active_conversation(page_id) do
      {:error, _} = err ->
        err

      _ ->
        insert_active(page_id, organization_id, project_id)
    end
  end

  @spec archive_active_conversation(String.t()) ::
          {:ok, PageConversation.t()} | :noop | {:error, Ecto.Changeset.t()}
  def archive_active_conversation(page_id) do
    case Repo.get_by(PageConversation, page_id: page_id, status: "active") do
      nil ->
        :noop

      conversation ->
        conversation
        |> PageConversation.archive_changeset()
        |> Repo.update()
    end
  end

  @spec get_conversation(String.t()) :: PageConversation.t() | nil
  def get_conversation(id), do: Repo.get(PageConversation, id)

  @spec get_active_conversation(String.t()) :: PageConversation.t() | nil
  def get_active_conversation(page_id) do
    Repo.get_by(PageConversation, page_id: page_id, status: "active")
  end

  @spec increment_conversation_stats(PageConversation.t(), keyword()) ::
          {non_neg_integer(), nil}
  def increment_conversation_stats(%PageConversation{id: id}, increments) do
    id
    |> PageConversationQueries.increment_stats()
    |> Repo.update_all(inc: increments)
  end

  # ── Runs ───────────────────────────────────────────────────────

  @spec create_run(map()) :: {:ok, PageRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) do
    %PageRun{}
    |> PageRun.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: PageRun.t() | nil
  def get_run(id), do: Repo.get(PageRun, id)

  @spec get_run!(String.t()) :: PageRun.t()
  def get_run!(id), do: Repo.get!(PageRun, id)

  @spec mark_run_running(PageRun.t()) :: {:ok, PageRun.t()} | {:error, Ecto.Changeset.t()}
  def mark_run_running(run) do
    run
    |> PageRun.running_changeset(%{status: "running", started_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @spec complete_run(PageRun.t(), map()) :: {:ok, PageRun.t()} | {:error, Ecto.Changeset.t()}
  def complete_run(run, attrs) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    merged =
      attrs
      |> Map.put_new(:status, "completed")
      |> Map.merge(%{completed_at: now, duration_ms: duration})

    run
    |> PageRun.completion_changeset(merged)
    |> Repo.update()
  end

  @spec fail_run(PageRun.t(), String.t()) :: {:ok, PageRun.t()} | {:error, Ecto.Changeset.t()}
  def fail_run(run, reason) when is_binary(reason) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    run
    |> PageRun.completion_changeset(%{
      status: "failed",
      error_message: reason,
      completed_at: now,
      duration_ms: duration
    })
    |> Repo.update()
  end

  @spec list_runs(String.t(), keyword()) :: [PageRun.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversation_id
    |> PageConversationQueries.runs_for_conversation(limit)
    |> Repo.all()
  end

  # ── Events ─────────────────────────────────────────────────────

  @spec append_event(PageRun.t(), map()) ::
          {:ok, PageEvent.t()} | {:error, Ecto.Changeset.t()}
  def append_event(%PageRun{id: run_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:sequence, fn -> next_sequence(run_id) end)
      |> Map.put(:run_id, run_id)

    %PageEvent{}
    |> PageEvent.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(String.t(), keyword()) :: [PageEvent.t()]
  def list_events(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    run_id
    |> PageConversationQueries.events_for_run(limit)
    |> Repo.all()
  end

  @spec list_recent_events_for_page(String.t(), keyword()) :: [PageEvent.t()]
  def list_recent_events_for_page(page_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    page_id
    |> PageConversationQueries.recent_events_for_page(limit)
    |> Repo.all()
  end

  @doc """
  Events from the currently active conversation of a page — what the chat UI
  shows and what feeds the LLM as conversational history. Older archived
  threads are excluded.
  """
  @spec list_active_conversation_events(String.t(), keyword()) :: [PageEvent.t()]
  def list_active_conversation_events(page_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    case get_active_conversation(page_id) do
      nil ->
        []

      conversation ->
        conversation.id
        |> PageConversationQueries.events_for_conversation(limit)
        |> Repo.all()
    end
  end

  @doc """
  Returns the chat history (user/assistant message pairs) for the active
  conversation of a page, as `[%{role, content}]` ordered oldest-first.
  Used to inject context into LLM prompts so the agent behaves like a true
  thread instead of a one-shot.
  """
  @spec thread_history(String.t(), keyword()) :: [%{role: String.t(), content: String.t()}]
  def thread_history(page_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # Fetch all chat-bearing events for the active conversation, then trim.
    # A conversation is bounded (a single editing session), so paginating
    # in SQL would slice the wrong end and lose the most recent messages.
    page_id
    |> list_active_conversation_events(limit: 1_000)
    |> Enum.flat_map(&event_to_history_message/1)
    |> Enum.take(-limit)
  end

  defp event_to_history_message(%{event_type: "user_message", content: content})
       when is_binary(content),
       do: [%{role: "user", content: content}]

  defp event_to_history_message(%{event_type: "assistant_message", content: content})
       when is_binary(content),
       do: [%{role: "assistant", content: content}]

  defp event_to_history_message(%{event_type: "completed", content: content})
       when is_binary(content),
       do: [%{role: "assistant", content: content}]

  defp event_to_history_message(_), do: []

  @spec next_sequence(String.t()) :: non_neg_integer()
  def next_sequence(run_id) do
    run_id
    |> PageConversationQueries.event_count()
    |> Repo.one() || 0
  end
end
