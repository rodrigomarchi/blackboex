defmodule Blackboex.PageConversations.PageConversation do
  @moduledoc """
  Container for AI chat runs scoped to a single Page. At most one conversation
  per page can be `active` at a time; older threads are archived. Mirrors the
  shape of `Blackboex.PlaygroundConversations.PlaygroundConversation` so the
  Page editor can offer the same chat experience as the Playground.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_conversations" do
    field :status, :string, default: "active"
    field :archived_at, :utc_datetime_usec

    field :total_runs, :integer, default: 0
    field :total_events, :integer, default: 0
    field :total_input_tokens, :integer, default: 0
    field :total_output_tokens, :integer, default: 0
    field :total_cost_cents, :integer, default: 0

    belongs_to :page, Blackboex.Pages.Page
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project

    has_many :runs, Blackboex.PageConversations.PageRun, foreign_key: :conversation_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:page_id, :organization_id, :project_id, :status])
    |> validate_required([:page_id, :organization_id, :project_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:page_id, name: :page_conversations_unique_active)
    |> foreign_key_constraint(:page_id)
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
    |> validate_number(:total_input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_cost_cents, greater_than_or_equal_to: 0)
  end

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
