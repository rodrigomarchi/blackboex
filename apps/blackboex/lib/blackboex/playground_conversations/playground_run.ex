defmodule Blackboex.PlaygroundConversations.PlaygroundRun do
  @moduledoc """
  Schema for a single AI agent execution inside a Playground conversation.

  Each run captures the trigger message, the code before/after, status, tokens
  and timing. Lifecycle:

      pending → running → completed | failed | canceled
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_run_types ~w(generate edit)
  @valid_statuses ~w(pending running completed failed canceled)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "playground_runs" do
    field :run_type, :string
    field :status, :string, default: "pending"
    field :trigger_message, :string

    field :code_before, :string
    field :code_after, :string
    field :run_summary, :string
    field :error_message, :string

    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :duration_ms, :integer

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :conversation, Blackboex.PlaygroundConversations.PlaygroundConversation
    belongs_to :playground, Blackboex.Playgrounds.Playground
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :user, Blackboex.Accounts.User, type: :id

    has_many :events, Blackboex.PlaygroundConversations.PlaygroundEvent, foreign_key: :run_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :conversation_id,
      :playground_id,
      :organization_id,
      :user_id,
      :run_type,
      :status,
      :trigger_message,
      :code_before
    ])
    |> validate_required([
      :conversation_id,
      :playground_id,
      :organization_id,
      :user_id,
      :run_type
    ])
    |> validate_inclusion(:run_type, @valid_run_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:playground_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)

  @spec running_changeset(t(), map()) :: Ecto.Changeset.t()
  def running_changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :started_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @spec completion_changeset(t(), map()) :: Ecto.Changeset.t()
  def completion_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :code_after,
      :run_summary,
      :error_message,
      :input_tokens,
      :output_tokens,
      :cost_cents,
      :completed_at,
      :duration_ms
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cost_cents, greater_than_or_equal_to: 0)
  end

  @spec valid_run_types() :: [String.t()]
  def valid_run_types, do: @valid_run_types

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses
end
