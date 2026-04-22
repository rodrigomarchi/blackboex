defmodule Blackboex.FlowConversations.FlowConversation do
  @moduledoc """
  Schema for AI chat conversations inside a Flow editor. Each Flow has at most
  one active conversation at a time; older threads are archived to preserve
  history without blocking new work. Separate from the API `Conversations`,
  `PlaygroundConversations`, and `PageConversations` domains so each editor can
  evolve independently.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flow_conversations" do
    field :status, :string, default: "active"
    field :archived_at, :utc_datetime_usec

    field :total_runs, :integer, default: 0
    field :total_events, :integer, default: 0
    field :total_input_tokens, :integer, default: 0
    field :total_output_tokens, :integer, default: 0
    field :total_cost_cents, :integer, default: 0

    belongs_to :flow, Blackboex.Flows.Flow
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project

    has_many :runs, Blackboex.FlowConversations.FlowRun, foreign_key: :conversation_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:flow_id, :organization_id, :project_id, :status])
    |> validate_required([:flow_id, :organization_id, :project_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:flow_id, name: :flow_conversations_unique_active)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:project_id)
  end

  @spec archive_changeset(t()) :: Ecto.Changeset.t()
  def archive_changeset(conversation) do
    conversation
    |> cast(%{}, [])
    |> put_change(:status, "archived")
    |> put_change(:archived_at, DateTime.utc_now())
  end

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

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
