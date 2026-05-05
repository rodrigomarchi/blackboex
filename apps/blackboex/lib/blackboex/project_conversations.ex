defmodule Blackboex.ProjectConversations do
  @moduledoc """
  Context for AI chat conversations attached to a Project-level agent
  session.

  A conversation is the top-level container (one active per Project). Runs
  are individual AI orchestration passes (`plan` for planning a multi-step
  change, `execute` for the runner). Events are atomic messages, plan
  artifacts, or terminal signals within a run, persisted so the chat
  timeline can be hydrated when the LiveView reconnects, and so the LLM can
  see prior turns as conversational history.

  Intentionally separate from `Blackboex.Conversations` (API),
  `Blackboex.PlaygroundConversations`, `Blackboex.PageConversations`, and
  `Blackboex.FlowConversations` so each agent domain evolves independently.
  """

  alias Blackboex.ProjectConversations.ProjectConversation
  alias Blackboex.ProjectConversations.ProjectConversationQueries
  alias Blackboex.ProjectConversations.ProjectEvent
  alias Blackboex.ProjectConversations.ProjectRun
  alias Blackboex.Repo

  # ── Conversations ──────────────────────────────────────────────

  @spec get_or_create_active_conversation(String.t(), String.t()) ::
          {:ok, ProjectConversation.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_active_conversation(project_id, organization_id) do
    case Repo.get_by(ProjectConversation, project_id: project_id, status: "active") do
      nil -> insert_active(project_id, organization_id)
      conversation -> {:ok, conversation}
    end
  end

  defp insert_active(project_id, organization_id) do
    %ProjectConversation{}
    |> ProjectConversation.changeset(%{
      project_id: project_id,
      organization_id: organization_id,
      status: "active"
    })
    |> Repo.insert()
    |> recover_unique_race(project_id)
  end

  defp recover_unique_race({:ok, _conv} = ok, _project_id), do: ok

  defp recover_unique_race({:error, changeset}, project_id) do
    if unique_project_id_violation?(changeset.errors) do
      case Repo.get_by(ProjectConversation, project_id: project_id, status: "active") do
        nil -> {:error, changeset}
        conv -> {:ok, conv}
      end
    else
      {:error, changeset}
    end
  end

  defp unique_project_id_violation?(errors) do
    Enum.any?(errors, &match?({:project_id, {_, [{:constraint, :unique} | _]}}, &1))
  end

  @doc """
  Archives the currently active conversation (if any) for the given project
  and creates a fresh active conversation. Used by the "New chat" action in
  the project agent UI to start a new thread without losing history.
  """
  @spec start_new_conversation(String.t(), String.t()) ::
          {:ok, ProjectConversation.t()} | {:error, Ecto.Changeset.t()}
  def start_new_conversation(project_id, organization_id) do
    _ = archive_active_conversation(project_id)

    %ProjectConversation{}
    |> ProjectConversation.changeset(%{
      project_id: project_id,
      organization_id: organization_id,
      status: "active"
    })
    |> Repo.insert()
  end

  @spec archive_active_conversation(String.t()) ::
          {:ok, ProjectConversation.t()} | :noop | {:error, Ecto.Changeset.t()}
  def archive_active_conversation(project_id) do
    case Repo.get_by(ProjectConversation, project_id: project_id, status: "active") do
      nil ->
        :noop

      conversation ->
        conversation
        |> ProjectConversation.archive_changeset()
        |> Repo.update()
    end
  end

  @spec get_conversation(String.t()) :: ProjectConversation.t() | nil
  def get_conversation(id), do: Repo.get(ProjectConversation, id)

  @spec get_active_conversation(String.t()) :: ProjectConversation.t() | nil
  def get_active_conversation(project_id) do
    Repo.get_by(ProjectConversation, project_id: project_id, status: "active")
  end

  @spec increment_conversation_stats(ProjectConversation.t(), keyword()) ::
          {non_neg_integer(), nil}
  def increment_conversation_stats(%ProjectConversation{id: id}, increments) do
    id
    |> ProjectConversationQueries.increment_stats()
    |> Repo.update_all(inc: increments)
  end

  # ── Runs ───────────────────────────────────────────────────────

  @spec create_run(map()) :: {:ok, ProjectRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) do
    %ProjectRun{}
    |> ProjectRun.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_run(String.t()) :: ProjectRun.t() | nil
  def get_run(id), do: Repo.get(ProjectRun, id)

  @spec get_run!(String.t()) :: ProjectRun.t()
  def get_run!(id), do: Repo.get!(ProjectRun, id)

  @spec mark_run_running(ProjectRun.t()) ::
          {:ok, ProjectRun.t()} | {:error, Ecto.Changeset.t()}
  def mark_run_running(run) do
    run
    |> ProjectRun.running_changeset(%{
      status: "running",
      started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @spec complete_run(ProjectRun.t(), map()) ::
          {:ok, ProjectRun.t()} | {:error, Ecto.Changeset.t()}
  def complete_run(run, attrs) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    merged =
      attrs
      |> Map.put_new(:status, "completed")
      |> Map.merge(%{completed_at: now, duration_ms: duration})

    run
    |> ProjectRun.completion_changeset(merged)
    |> Repo.update()
  end

  @spec fail_run(ProjectRun.t(), String.t()) ::
          {:ok, ProjectRun.t()} | {:error, Ecto.Changeset.t()}
  def fail_run(run, reason) when is_binary(reason) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, run.started_at || now, :millisecond)

    run
    |> ProjectRun.completion_changeset(%{
      status: "failed",
      error_message: reason,
      completed_at: now,
      duration_ms: duration
    })
    |> Repo.update()
  end

  @spec list_runs(String.t(), keyword()) :: [ProjectRun.t()]
  def list_runs(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    conversation_id
    |> ProjectConversationQueries.runs_for_conversation(limit)
    |> Repo.all()
  end

  # ── Events ─────────────────────────────────────────────────────

  @spec append_event(ProjectRun.t(), map()) ::
          {:ok, ProjectEvent.t()} | {:error, Ecto.Changeset.t()}
  def append_event(%ProjectRun{id: run_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:sequence, fn -> next_sequence(run_id) end)
      |> Map.put(:run_id, run_id)

    %ProjectEvent{}
    |> ProjectEvent.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(String.t(), keyword()) :: [ProjectEvent.t()]
  def list_events(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    run_id
    |> ProjectConversationQueries.events_for_run(limit)
    |> Repo.all()
  end

  @spec list_recent_events_for_project(String.t(), keyword()) :: [ProjectEvent.t()]
  def list_recent_events_for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    project_id
    |> ProjectConversationQueries.recent_events_for_project(limit)
    |> Repo.all()
  end

  @doc """
  Returns events for the ACTIVE conversation of a project. Used to hydrate
  the chat UI when the LiveView reconnects.
  """
  @spec list_active_conversation_events(String.t(), keyword()) :: [ProjectEvent.t()]
  def list_active_conversation_events(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    case get_active_conversation(project_id) do
      nil ->
        []

      conversation ->
        conversation.id
        |> ProjectConversationQueries.events_for_conversation(limit)
        |> Repo.all()
    end
  end

  @spec next_sequence(String.t()) :: non_neg_integer()
  def next_sequence(run_id) do
    run_id
    |> ProjectConversationQueries.event_count()
    |> Repo.one() || 0
  end
end
