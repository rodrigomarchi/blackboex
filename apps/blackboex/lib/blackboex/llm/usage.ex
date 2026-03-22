defmodule Blackboex.LLM.Usage do
  @moduledoc """
  Schema for tracking LLM usage per request. Stores token counts,
  cost, provider, and operation type.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "llm_usage" do
    field :provider, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :operation, :string
    field :duration_ms, :integer, default: 0

    belongs_to :user, Blackboex.Accounts.User, type: :id
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :api, Blackboex.Apis.Api

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :provider,
      :model,
      :input_tokens,
      :output_tokens,
      :cost_cents,
      :operation,
      :api_id,
      :duration_ms
    ])
    |> validate_required([:provider, :model, :operation])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, _attrs, _metadata), do: change(struct)
end
