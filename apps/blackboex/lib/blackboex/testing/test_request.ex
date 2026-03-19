defmodule Blackboex.Testing.TestRequest do
  @moduledoc """
  Schema for persisted API test requests and their responses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_methods ~w(GET POST PUT PATCH DELETE)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "test_requests" do
    field :method, :string
    field :path, :string
    field :headers, :map, default: %{}
    field :body, :string
    field :response_status, :integer
    field :response_headers, :map, default: %{}
    field :response_body, :string
    field :duration_ms, :integer

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_request, attrs) do
    test_request
    |> cast(attrs, [
      :api_id,
      :user_id,
      :method,
      :path,
      :headers,
      :body,
      :response_status,
      :response_headers,
      :response_body,
      :duration_ms
    ])
    |> validate_required([:api_id, :method, :path])
    |> validate_inclusion(:method, @valid_methods)
    |> validate_length(:path, max: 2048)
    |> validate_length(:body, max: 1_048_576)
  end
end
