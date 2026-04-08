defmodule Blackboex.FlowExecutions.NodeExecution do
  @moduledoc """
  Schema for node executions. Tracks individual node runs within a flow execution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @valid_statuses ~w(pending running completed failed skipped)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "node_executions" do
    field :node_id, :string
    field :node_type, :string
    field :status, :string, default: "pending"
    field :input, :map
    field :output, :map
    field :error, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :duration_ms, :integer

    belongs_to :flow_execution, Blackboex.FlowExecutions.FlowExecution

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(node_execution, attrs) do
    node_execution
    |> cast(attrs, [
      :flow_execution_id,
      :node_id,
      :node_type,
      :status,
      :input,
      :output,
      :error,
      :started_at,
      :finished_at,
      :duration_ms
    ])
    |> validate_required([:flow_execution_id, :node_id, :node_type, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:flow_execution_id)
    |> unique_constraint([:flow_execution_id, :node_id])
  end
end
