defmodule Blackboex.PlaygroundExecutionsFixtures do
  @moduledoc """
  Test helpers for creating PlaygroundExecution entities.
  """

  alias Blackboex.Playgrounds.PlaygroundExecution
  alias Blackboex.Repo

  @doc """
  Creates a playground execution.

  ## Options

    * `:playground` - the playground (required, or auto-created)
    * `:run_number` - run number (default: 1)
    * `:code_snapshot` - code that was run (default: "IO.puts(:ok)")
    * `:output` - execution output (default: "ok")
    * `:status` - execution status (default: "success")
    * `:duration_ms` - duration in ms (default: 42)

  Returns the PlaygroundExecution struct.
  """
  @spec execution_fixture(map()) :: PlaygroundExecution.t()
  def execution_fixture(attrs \\ %{}) do
    playground =
      attrs[:playground] ||
        Blackboex.PlaygroundsFixtures.playground_fixture(Map.take(attrs, [:user, :org, :project]))

    known_keys = [:playground, :user, :org, :project]
    extra = Map.drop(attrs, known_keys)

    {:ok, execution} =
      %PlaygroundExecution{}
      |> PlaygroundExecution.changeset(
        Map.merge(
          %{
            playground_id: playground.id,
            run_number: 1,
            code_snapshot: "IO.puts(:ok)",
            status: "success"
          },
          extra
        )
      )
      |> Ecto.Changeset.put_change(:output, Map.get(extra, :output, "ok"))
      |> Ecto.Changeset.put_change(:duration_ms, Map.get(extra, :duration_ms, 42))
      |> Repo.insert()

    execution
  end
end
