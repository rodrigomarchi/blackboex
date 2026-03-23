defmodule Blackboex.Apis.DataStore.Entry do
  @moduledoc """
  Schema for API data entries. Each entry stores a key-value pair
  scoped to a specific API, with the value stored as JSONB.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_data" do
    field :key, :string
    field :value, :map

    belongs_to :api, Blackboex.Apis.Api

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:api_id, :key, :value])
    |> validate_required([:api_id, :key, :value])
    |> unique_constraint([:api_id, :key])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata) do
    changeset(struct, attrs)
  end
end
