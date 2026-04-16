defmodule Blackboex.Playgrounds.ExecutionQueries do
  @moduledoc """
  Composable query builders for the PlaygroundExecution schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Playgrounds.PlaygroundExecution

  @spec list_for_playground(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_playground(playground_id) do
    PlaygroundExecution
    |> where([e], e.playground_id == ^playground_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(50)
  end

  @spec latest_run_number(Ecto.UUID.t()) :: Ecto.Query.t()
  def latest_run_number(playground_id) do
    PlaygroundExecution
    |> where([e], e.playground_id == ^playground_id)
    |> select([e], max(e.run_number))
  end

  @spec beyond_retention(Ecto.UUID.t(), pos_integer()) :: Ecto.Query.t()
  def beyond_retention(playground_id, keep \\ 50) do
    kept_ids =
      PlaygroundExecution
      |> where([e], e.playground_id == ^playground_id)
      |> order_by([e], desc: e.inserted_at)
      |> limit(^keep)
      |> select([e], e.id)

    PlaygroundExecution
    |> where([e], e.playground_id == ^playground_id)
    |> where([e], e.id not in subquery(kept_ids))
  end
end
