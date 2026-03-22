defmodule Blackboex.Audit.Version do
  @moduledoc """
  ExAudit version schema.
  Tracks row-level changes automatically on configured schemas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.Accounts.User

  @type t :: %__MODULE__{}

  schema "versions" do
    field :patch, ExAudit.Type.Patch
    field :entity_id, :binary_id
    field :entity_schema, ExAudit.Type.Schema
    field :action, ExAudit.Type.Action
    field :recorded_at, :utc_datetime_usec
    field :rollback, :boolean, default: false

    # Custom fields
    belongs_to :actor, User
    field :ip_address, :string
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch, :entity_id, :entity_schema, :action, :recorded_at, :rollback])
    |> cast(params, [:actor_id, :ip_address])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, _attrs, _metadata), do: change(struct)
end
