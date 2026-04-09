defmodule Blackboex.FlowExecutions.FlowExecution do
  @moduledoc """
  Schema for flow executions. Tracks individual runs of a flow.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @valid_statuses ~w(pending running completed failed halted)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flow_executions" do
    field :status, :string, default: "pending"
    field :input, :map, default: %{}
    field :output, :map
    field :shared_state, :map, default: %{}
    field :error, :string
    field :halted_state, :binary
    field :wait_event_type, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :duration_ms, :integer

    belongs_to :flow, Blackboex.Flows.Flow
    belongs_to :organization, Blackboex.Organizations.Organization

    has_many :node_executions, Blackboex.FlowExecutions.NodeExecution

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :flow_id,
      :organization_id,
      :status,
      :input,
      :output,
      :shared_state,
      :error,
      :halted_state,
      :wait_event_type,
      :started_at,
      :finished_at,
      :duration_ms
    ])
    |> validate_required([:flow_id, :organization_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:organization_id)
  end
end
