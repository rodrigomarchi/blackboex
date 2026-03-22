defmodule Blackboex.Apis.ApiKey do
  @moduledoc """
  Schema for API keys. Each key belongs to an API and organization.
  Keys are stored as one-way SHA-256 hashes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_keys" do
    field :key_hash, :binary
    field :key_prefix, :string
    field :label, :string
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :rate_limit, :integer

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :organization, Blackboex.Organizations.Organization

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [
      :key_hash,
      :key_prefix,
      :label,
      :last_used_at,
      :expires_at,
      :revoked_at,
      :rate_limit,
      :api_id,
      :organization_id
    ])
    |> validate_required([:key_hash, :key_prefix, :api_id, :organization_id])
    |> validate_length(:label, max: 200)
    |> validate_length(:key_prefix, max: 20)
    |> validate_number(:rate_limit, greater_than: 0)
    |> unique_constraint(:key_hash)
    |> foreign_key_constraint(:api_id)
    |> foreign_key_constraint(:organization_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, _attrs, _metadata), do: change(struct)
end
