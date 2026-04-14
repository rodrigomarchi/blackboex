defmodule Blackboex.Billing.DailyUsage do
  @moduledoc """
  Schema for aggregated daily usage per organization.
  Populated by UsageAggregationWorker from UsageEvent records.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.Organizations.Organization

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "daily_usage" do
    belongs_to :organization, Organization
    field :project_id, :binary_id
    field :date, :date
    field :api_invocations, :integer, default: 0
    field :llm_generations, :integer, default: 0
    field :tokens_input, :integer, default: 0
    field :tokens_output, :integer, default: 0
    field :llm_cost_cents, :integer, default: 0

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(daily_usage, attrs) do
    daily_usage
    |> cast(attrs, [
      :organization_id,
      :project_id,
      :date,
      :api_invocations,
      :llm_generations,
      :tokens_input,
      :tokens_output,
      :llm_cost_cents
    ])
    |> validate_required([:organization_id, :date])
    |> validate_number(:api_invocations, greater_than_or_equal_to: 0)
    |> validate_number(:llm_generations, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_input, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_output, greater_than_or_equal_to: 0)
    |> validate_number(:llm_cost_cents, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :project_id, :date])
    |> foreign_key_constraint(:organization_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
