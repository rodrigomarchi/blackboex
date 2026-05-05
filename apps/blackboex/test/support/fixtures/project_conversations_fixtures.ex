defmodule Blackboex.ProjectConversationsFixtures do
  @moduledoc """
  Test helpers for creating ProjectConversation, ProjectRun, and ProjectEvent
  entities. Uses `Repo` directly to avoid coupling fixtures to the facade —
  the facade's own tests can therefore consume these fixtures without
  circular dependency.
  """

  import Ecto.Query, only: [from: 2]

  alias Blackboex.ProjectConversations.ProjectConversation
  alias Blackboex.ProjectConversations.ProjectEvent
  alias Blackboex.ProjectConversations.ProjectRun
  alias Blackboex.Repo

  @doc """
  Gets or creates an active ProjectConversation for the given project.

  Options:
    * `:project` — the Project (auto-created via `ProjectsFixtures.project_fixture/1` if absent)
    * `:user`, `:org` — forwarded to project auto-creation

  Returns the ProjectConversation struct.
  """
  @spec project_conversation_fixture(map()) :: ProjectConversation.t()
  def project_conversation_fixture(attrs \\ %{}) do
    project =
      attrs[:project] ||
        Blackboex.ProjectsFixtures.project_fixture(Map.take(attrs, [:user, :org]))

    case Repo.get_by(ProjectConversation, project_id: project.id, status: "active") do
      %ProjectConversation{} = existing ->
        existing

      nil ->
        {:ok, conv} =
          %ProjectConversation{}
          |> ProjectConversation.changeset(%{
            project_id: project.id,
            organization_id: project.organization_id,
            status: "active"
          })
          |> Repo.insert()

        conv
    end
  end

  @doc """
  Creates a ProjectRun for the given (or auto-created) conversation.

  Options:
    * `:conversation` — parent ProjectConversation (auto-created if absent)
    * `:user` — owning User (auto-created if absent)
    * `:run_type` — default `"plan"`
    * `:status` — default `"pending"`
    * `:trigger_message` — passed through

  Returns the ProjectRun struct.
  """
  @spec project_run_fixture(map()) :: ProjectRun.t()
  def project_run_fixture(attrs \\ %{}) do
    conversation =
      attrs[:conversation] ||
        project_conversation_fixture(Map.take(attrs, [:project, :user, :org]))

    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()

    known_keys = [:conversation, :project, :user, :org]

    base = %{
      conversation_id: conversation.id,
      project_id: conversation.project_id,
      organization_id: conversation.organization_id,
      user_id: user.id,
      run_type: "plan",
      status: "pending",
      trigger_message: "build a CRUD for blog posts"
    }

    {:ok, run} =
      %ProjectRun{}
      |> ProjectRun.changeset(Map.merge(base, Map.drop(attrs, known_keys)))
      |> Repo.insert()

    run
  end

  @doc """
  Creates a ProjectEvent for the given (or auto-created) run.

  Auto-assigns the next `sequence` per run if not provided.
  """
  @spec project_event_fixture(map()) :: ProjectEvent.t()
  def project_event_fixture(attrs \\ %{}) do
    run =
      attrs[:run] ||
        project_run_fixture(Map.take(attrs, [:conversation, :project, :user, :org]))

    known_keys = [:run, :conversation, :project, :user, :org]
    extra = Map.drop(attrs, known_keys)

    sequence = Map.get(extra, :sequence, next_sequence(run.id))

    base = %{
      run_id: run.id,
      sequence: sequence,
      event_type: "user_message",
      content: "hello",
      metadata: %{}
    }

    final_attrs =
      base
      |> Map.merge(Map.drop(extra, [:sequence]))
      |> Map.put(:sequence, sequence)

    {:ok, event} =
      %ProjectEvent{}
      |> ProjectEvent.changeset(final_attrs)
      |> Repo.insert()

    event
  end

  @doc """
  Named setup: creates a ProjectConversation for an existing user + org +
  project in context.

  Usage:
      setup [:register_and_log_in_user, :create_project, :create_project_conversation]
  """
  @spec create_project_conversation(map()) :: map()
  def create_project_conversation(%{project: _project} = ctx) do
    %{project_conversation: project_conversation_fixture(Map.take(ctx, [:project, :user, :org]))}
  end

  defp next_sequence(run_id) do
    max =
      Repo.one(from e in ProjectEvent, where: e.run_id == ^run_id, select: max(e.sequence)) || -1

    max + 1
  end
end
