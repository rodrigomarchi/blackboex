defmodule Blackboex.Playgrounds do
  @moduledoc """
  The Playgrounds context. Manages interactive code playgrounds within projects
  for Elixir experimentation and prototyping.
  """

  alias Blackboex.Playgrounds.ExecutionQueries
  alias Blackboex.Playgrounds.Executor
  alias Blackboex.Playgrounds.Playground
  alias Blackboex.Playgrounds.PlaygroundExecution
  alias Blackboex.Playgrounds.PlaygroundQueries
  alias Blackboex.Repo

  # ── Playground CRUD ────────────────────────────────────────

  @spec create_playground(map()) :: {:ok, Playground.t()} | {:error, Ecto.Changeset.t()}
  def create_playground(attrs) do
    %Playground{}
    |> Playground.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_playgrounds(Ecto.UUID.t()) :: [Playground.t()]
  def list_playgrounds(project_id) do
    project_id |> PlaygroundQueries.list_for_project() |> Repo.all()
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

  @spec update_playground(Playground.t(), map()) ::
          {:ok, Playground.t()} | {:error, Ecto.Changeset.t()}
  def update_playground(%Playground{} = playground, attrs) do
    playground
    |> Playground.update_changeset(attrs)
    |> Repo.update()
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
        # Save the code and store the error as output
        _save_result =
          playground
          |> Playground.update_changeset(%{code: source_code, last_output: "Error: #{reason}"})
          |> Repo.update()

        {:error, reason}
    end
  end

  @doc """
  Executes code in the sandbox without persisting results.
  Returns the raw executor result for the caller to handle persistence.
  """
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

  # ── AI edits ──────────────────────────────────────────────

  @doc """
  Applies an AI-generated code change to a playground atomically.

  Creates a `PlaygroundExecution` snapshot with status `"ai_snapshot"` and
  `code_snapshot` set to the code BEFORE the edit (so the history sidebar
  can be used to revert), then updates `playground.code` with the new code.

  Both inserts happen inside a single `Repo.transaction`; if either fails,
  the whole change is rolled back.
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
