defmodule Blackboex.Conversations.Conversation do
  @moduledoc """
  Schema for agent conversations. Each API has at most one conversation
  that serves as the container for all agent runs and their events.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"

    field :total_runs, :integer, default: 0
    field :total_events, :integer, default: 0
    field :total_input_tokens, :integer, default: 0
    field :total_output_tokens, :integer, default: 0
    field :total_cost_cents, :integer, default: 0

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :organization, Blackboex.Organizations.Organization

    has_many :runs, Blackboex.Conversations.Run

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:api_id, :organization_id, :title, :status])
    |> validate_required([:api_id, :organization_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:title, max: 500)
    |> unique_constraint(:api_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)

  @spec stats_changeset(t(), map()) :: Ecto.Changeset.t()
  def stats_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :total_runs,
      :total_events,
      :total_input_tokens,
      :total_output_tokens,
      :total_cost_cents
    ])
    |> validate_number(:total_runs, greater_than_or_equal_to: 0)
    |> validate_number(:total_events, greater_than_or_equal_to: 0)
    |> validate_number(:total_cost_cents, greater_than_or_equal_to: 0)
  end
end
