defmodule Blackboex.Playgrounds.PlaygroundExecution do
  @moduledoc """
  Schema for playground execution records. Each execution captures a snapshot
  of the code run, its output, status, and duration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(running success error ai_snapshot)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "playground_executions" do
    field :run_number, :integer
    field :code_snapshot, :string
    field :output, :string
    field :status, :string, default: "running"
    field :duration_ms, :integer

    belongs_to :playground, Blackboex.Playgrounds.Playground

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [:playground_id, :run_number, :code_snapshot, :status])
    |> validate_required([:playground_id, :run_number, :code_snapshot, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:run_number, greater_than: 0)
    |> foreign_key_constraint(:playground_id)
    |> unique_constraint([:playground_id, :run_number])
  end

  @spec ai_snapshot_changeset(t(), map()) :: Ecto.Changeset.t()
  def ai_snapshot_changeset(execution, attrs) do
    code_snapshot =
      Map.get(attrs, :code_snapshot, Map.get(attrs, "code_snapshot", "")) || ""

    execution
    |> cast(attrs, [:playground_id, :run_number, :status])
    |> put_change(:code_snapshot, code_snapshot)
    |> validate_required([:playground_id, :run_number, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:run_number, greater_than: 0)
    |> foreign_key_constraint(:playground_id)
    |> unique_constraint([:playground_id, :run_number])
  end

  @spec complete_changeset(t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(execution, attrs) do
    execution
    |> cast(attrs, [:output, :status, :duration_ms])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_length(:output, max: 65_536)
  end
end
