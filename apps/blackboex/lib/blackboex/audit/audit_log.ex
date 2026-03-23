defmodule Blackboex.Audit.AuditLog do
  @moduledoc """
  Schema for operation-level audit logs.
  Records explicit business actions performed by users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.Accounts.User
  alias Blackboex.Organizations.Organization

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_logs" do
    belongs_to :user, User, type: :id
    belongs_to :organization, Organization
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string

    timestamps(updated_at: false)
  end

  @doc """
  Admin changeset for Backpex. Audit logs are immutable — no edits allowed.
  """
  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(audit_log, attrs, _metadata) do
    changeset(audit_log, attrs)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :action,
      :resource_type,
      :resource_id,
      :metadata,
      :ip_address
    ])
    |> validate_required([:action])
    |> validate_length(:action, max: 255)
    |> validate_length(:resource_type, max: 255)
    |> validate_length(:resource_id, max: 255)
    |> validate_length(:ip_address, max: 45)
  end
end
