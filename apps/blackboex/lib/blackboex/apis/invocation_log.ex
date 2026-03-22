defmodule Blackboex.Apis.InvocationLog do
  @moduledoc """
  Schema for API invocation logs. Immutable — never updated after insert.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_logs" do
    field :method, :string
    field :path, :string
    field :status_code, :integer
    field :duration_ms, :integer
    field :request_body_size, :integer
    field :response_body_size, :integer
    field :ip_address, :string

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :api_key, Blackboex.Apis.ApiKey

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :api_id,
      :api_key_id,
      :method,
      :path,
      :status_code,
      :duration_ms,
      :request_body_size,
      :response_body_size,
      :ip_address
    ])
    |> validate_required([:api_id, :method])
    |> validate_length(:method, max: 10)
    |> validate_length(:path, max: 2048)
    |> validate_length(:ip_address, max: 45)
    |> validate_number(:status_code, greater_than_or_equal_to: 100, less_than_or_equal_to: 599)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:request_body_size, greater_than_or_equal_to: 0)
    |> validate_number(:response_body_size, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:api_id)
    |> foreign_key_constraint(:api_key_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, _attrs, _metadata), do: change(struct)
end
