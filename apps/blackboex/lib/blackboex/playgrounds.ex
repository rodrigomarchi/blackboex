defmodule Blackboex.Playgrounds do
  @moduledoc """
  The Playgrounds context. Manages interactive code playgrounds within projects
  for Elixir experimentation and prototyping.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Playgrounds.ExecutionQueries
  alias Blackboex.Playgrounds.Executor
  alias Blackboex.Playgrounds.Playground
  alias Blackboex.Playgrounds.PlaygroundExecution
  alias Blackboex.Playgrounds.PlaygroundQueries
  alias Blackboex.Repo

  # ── Playground CRUD ────────────────────────────────────────

  @spec create_playground(map()) ::
          {:ok, Playground.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_playground(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]
    project_id = attrs[:project_id] || attrs["project_id"]

    with :ok <- ensure_project_in_org(project_id, org_id) do
      %Playground{}
      |> Playground.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec list_playgrounds(Ecto.UUID.t()) :: [Playground.t()]
  def list_playgrounds(project_id) do
    project_id |> PlaygroundQueries.list_for_project() |> Repo.all()
  end

  @spec list_for_project(Ecto.UUID.t(), keyword()) :: [Playground.t()]
  def list_for_project(project_id, opts \\ []) do
    project_id |> PlaygroundQueries.list_for_project_sorted(opts) |> Repo.all()
  end

  @spec list_playgrounds(Ecto.UUID.t(), keyword()) :: [Playground.t()]
  def list_playgrounds(project_id, opts) do
    query = PlaygroundQueries.list_for_project(project_id)

    query =
      case Keyword.get(opts, :search) do
        nil -> query
        "" -> query
        term -> PlaygroundQueries.search(query, term)
      end

    Repo.all(query)
  end

  @spec get_playground(Ecto.UUID.t(), Ecto.UUID.t()) :: Playground.t() | nil
  def get_playground(project_id, playground_id) do
    project_id |> PlaygroundQueries.by_project_and_id(playground_id) |> Repo.one()
  end

  @spec get_playground_by_slug(Ecto.UUID.t(), String.t()) :: Playground.t() | nil
  def get_playground_by_slug(project_id, slug) do
    project_id |> PlaygroundQueries.by_project_and_slug(slug) |> Repo.one()
  end

  @doc """
  Fetches a Playground by organization_id and playground_id. Returns `nil` when not found or
  the playground does not belong to the given organization.
  """
  @spec get_for_org(Ecto.UUID.t(), Ecto.UUID.t()) :: Playground.t() | nil
  def get_for_org(org_id, playground_id) do
    org_id |> PlaygroundQueries.by_org_and_id(playground_id) |> Repo.one()
  end

  @spec update_playground(Playground.t(), map()) ::
          {:ok, Playground.t()} | {:error, Ecto.Changeset.t()}
  def update_playground(%Playground{} = playground, attrs) do
    playground
    |> Playground.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a Playground to a different project within the same organization.

  Validates that `new_project_id` belongs to the same org as the playground.
  """
  @spec move_playground(Playground.t(), Ecto.UUID.t()) ::
          {:ok, Playground.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def move_playground(%Playground{} = playground, new_project_id) do
    with :ok <- ensure_project_in_org(new_project_id, playground.organization_id) do
      playground
      |> Playground.move_project_changeset(%{project_id: new_project_id})
      |> Repo.update()
    end
  end

  @spec delete_playground(Playground.t()) ::
          {:ok, Playground.t()} | {:error, Ecto.Changeset.t()}
  def delete_playground(%Playground{} = playground) do
    Repo.delete(playground)
  end

  @spec change_playground(Playground.t(), map()) :: Ecto.Changeset.t()
  def change_playground(%Playground{} = playground, attrs \\ %{}) do
    Playground.changeset(playground, attrs)
  end

  # ── Execution ──────────────────────────────────────────────

  @spec execute_code(Playground.t(), String.t()) ::
          {:ok, Playground.t()} | {:error, String.t()}
  def execute_code(%Playground{} = playground, source_code) do
    case Executor.execute(source_code, playground.user_id) do
      {:ok, output} ->
        {:ok, _updated} =
          playground
          |> Playground.update_changeset(%{code: source_code, last_output: output})
          |> Repo.update()

      {:error, reason} ->
        _save_result =
          playground
          |> Playground.update_changeset(%{code: source_code, last_output: "Error: #{reason}"})
          |> Repo.update()

        {:error, reason}
    end
  end

  @doc "Executes code in the sandbox without persisting results."
  @spec execute_code_raw(Playground.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def execute_code_raw(%Playground{} = playground, source_code) do
    Executor.execute(source_code, playground.user_id)
  end

  # ── Execution History ─────────────────────────────────────

  @spec create_execution(Playground.t(), String.t()) ::
          {:ok, PlaygroundExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_execution(%Playground{} = playground, code_snapshot) do
    next_number =
      case playground.id |> ExecutionQueries.latest_run_number() |> Repo.one() do
        nil -> 1
        n -> n + 1
      end

    %PlaygroundExecution{}
    |> PlaygroundExecution.changeset(%{
      playground_id: playground.id,
      run_number: next_number,
      code_snapshot: code_snapshot,
      status: "running"
    })
    |> Repo.insert()
  end

  @spec complete_execution(PlaygroundExecution.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, PlaygroundExecution.t()} | {:error, Ecto.Changeset.t()}
  def complete_execution(%PlaygroundExecution{} = execution, output, status, duration_ms) do
    execution
    |> PlaygroundExecution.complete_changeset(%{
      output: output,
      status: status,
      duration_ms: duration_ms
    })
    |> Repo.update()
  end

  @spec list_executions(Ecto.UUID.t()) :: [PlaygroundExecution.t()]
  def list_executions(playground_id) do
    playground_id |> ExecutionQueries.list_for_playground() |> Repo.all()
  end

  @spec get_execution(Ecto.UUID.t()) :: PlaygroundExecution.t() | nil
  def get_execution(execution_id) do
    Repo.get(PlaygroundExecution, execution_id)
  end

  @spec cleanup_old_executions(Ecto.UUID.t()) :: {non_neg_integer(), nil | [term()]}
  def cleanup_old_executions(playground_id) do
    playground_id |> ExecutionQueries.beyond_retention() |> Repo.delete_all()
  end

  # ── Private ───────────────────────────────────────────────

  defp ensure_project_in_org(nil, _org_id), do: :ok
  defp ensure_project_in_org(_project_id, nil), do: :ok

  defp ensure_project_in_org(project_id, org_id) do
    query =
      from p in Blackboex.Projects.Project,
        where: p.id == ^project_id and p.organization_id == ^org_id,
        select: 1

    if Repo.exists?(query), do: :ok, else: {:error, :forbidden}
  end

  # ── AI edits ──────────────────────────────────────────────

  @doc """
  Applies an AI-generated code change to a playground atomically.
  Creates an `"ai_snapshot"` execution with `code_snapshot` set to the code BEFORE the edit
  (enabling revert via history), then updates `playground.code`. Both writes are transactional.
  """
  @spec record_ai_edit(Playground.t(), String.t(), String.t()) ::
          {:ok, %{playground: Playground.t(), snapshot: PlaygroundExecution.t()}}
          | {:error, term()}
  def record_ai_edit(%Playground{} = playground, new_code, code_before)
      when is_binary(new_code) and is_binary(code_before) do
    Repo.transaction(fn ->
      next_number =
        case playground.id |> ExecutionQueries.latest_run_number() |> Repo.one() do
          nil -> 1
          n -> n + 1
        end

      snapshot_changeset =
        %PlaygroundExecution{}
        |> PlaygroundExecution.ai_snapshot_changeset(%{
          playground_id: playground.id,
          run_number: next_number,
          code_snapshot: code_before,
          status: "ai_snapshot"
        })

      with {:ok, snapshot} <- Repo.insert(snapshot_changeset),
           {:ok, updated} <-
             playground
             |> Playground.update_changeset(%{code: new_code})
             |> Repo.update() do
        %{playground: updated, snapshot: snapshot}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
