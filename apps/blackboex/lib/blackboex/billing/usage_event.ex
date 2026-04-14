defmodule Blackboex.Billing.UsageEvent do
  @moduledoc """
  Schema for granular usage events.
  Immutable log of API invocations and LLM generations per organization.
  Aggregated daily by UsageAggregationWorker into DailyUsage.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.Organizations.Organization

  @type t :: %__MODULE__{}

  @valid_event_types ~w(api_invocation llm_generation)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "usage_events" do
    belongs_to :organization, Organization
    field :project_id, :binary_id
    field :event_type, :string
    field :metadata, :map, default: %{}

    timestamps(updated_at: false)
  end

  @max_metadata_keys 50

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:organization_id, :project_id, :event_type, :metadata])
    |> validate_required([:organization_id, :event_type])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_metadata_size()
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_metadata_size(changeset) do
    validate_change(changeset, :metadata, fn :metadata, value ->
      if is_map(value) and map_size(value) > @max_metadata_keys do
        [metadata: "cannot exceed #{@max_metadata_keys} keys"]
      else
        []
      end
    end)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
