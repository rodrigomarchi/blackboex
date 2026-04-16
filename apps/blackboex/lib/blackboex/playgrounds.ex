defmodule Blackboex.Playgrounds do
  @moduledoc """
  The Playgrounds context. Manages interactive code playgrounds within projects
  for Elixir experimentation and prototyping.
  """

  alias Blackboex.Playgrounds.Executor
  alias Blackboex.Playgrounds.Playground
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
end
