defmodule Blackboex.Organizations.Invitation do
  @moduledoc "Pending invitation to join an organization."
  use Ecto.Schema

  import Ecto.Changeset

  alias Blackboex.Accounts.User
  alias Blackboex.Organizations.Organization

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "org_invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :invited_by, User, foreign_key: :invited_by_id, type: :id

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :organization_id,
      :email,
      :role,
      :token_hash,
      :invited_by_id,
      :expires_at,
      :accepted_at
    ])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:organization_id, :email, :role, :token_hash, :expires_at])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> unique_constraint(:token_hash)
    |> unique_constraint([:organization_id, :email],
      name: :org_invitations_pending_email_unique
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()
end
