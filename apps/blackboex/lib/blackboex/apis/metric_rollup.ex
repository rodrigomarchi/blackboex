defmodule Blackboex.Apis.MetricRollup do
  @moduledoc """
  Hourly aggregated metrics per API. Populated by MetricRollupWorker.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_metric_rollups" do
    field :date, :date
    field :hour, :integer
    field :invocations, :integer, default: 0
    field :errors, :integer, default: 0
    field :avg_duration_ms, :float, default: 0.0
    field :p95_duration_ms, :float, default: 0.0
    field :unique_consumers, :integer, default: 0

    belongs_to :api, Blackboex.Apis.Api

    timestamps()
  end

  @required_fields [:api_id, :date, :hour]
  @optional_fields [:invocations, :errors, :avg_duration_ms, :p95_duration_ms, :unique_consumers]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(rollup, attrs) do
    rollup
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:invocations, greater_than_or_equal_to: 0)
    |> validate_number(:errors, greater_than_or_equal_to: 0)
    |> validate_number(:avg_duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:p95_duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:unique_consumers, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:api_id)
    |> unique_constraint([:api_id, :date, :hour])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
