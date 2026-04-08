defmodule Blackboex.FlowSecrets.FlowSecret do
  @moduledoc """
  Schema for FlowSecrets. Stores encrypted (Base64-encoded) secret values
  scoped to an organization.

  Note: "encryption" is Base64 encoding for MVP — placeholder for Cloak later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flow_secrets" do
    field :name, :string
    field :encrypted_value, :binary

    belongs_to :organization, Blackboex.Organizations.Organization

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [:name, :organization_id])
    |> validate_required([:name, :organization_id])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_]+$/,
      message: "must contain only alphanumeric characters and underscores"
    )
    |> unique_constraint([:organization_id, :name])
    |> maybe_encrypt_value(attrs)
    |> validate_required([:encrypted_value])
  end

  @spec encrypt_value(String.t()) :: binary()
  def encrypt_value(plaintext) do
    Base.encode64(plaintext)
  end

  @spec decrypt_value(binary()) :: String.t()
  def decrypt_value(encrypted) do
    Base.decode64!(encrypted)
  end

  defp maybe_encrypt_value(changeset, attrs) do
    value = attrs[:value] || attrs["value"]

    case value do
      nil -> changeset
      v -> put_change(changeset, :encrypted_value, encrypt_value(v))
    end
  end
end
