defmodule Blackboex.FlowConversations.FlowRun do
  @moduledoc """
  Single AI agent execution inside a Flow conversation. Captures the trigger
  message, the flow definition before/after (JSONB maps in the canonical
  BlackboexFlow shape), status, tokens and timing. Lifecycle:

      pending → running → completed | failed | canceled
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_run_types ~w(generate edit)
  @valid_statuses ~w(pending running completed failed canceled)

  @max_message_chars 10_000

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flow_runs" do
    field :run_type, :string
    field :status, :string, default: "pending"
    field :trigger_message, :string

    field :definition_before, :map, default: %{}
    field :definition_after, :map
    field :run_summary, :string
    field :error_message, :string

    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :duration_ms, :integer

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :conversation, Blackboex.FlowConversations.FlowConversation
    belongs_to :flow, Blackboex.Flows.Flow
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :user, Blackboex.Accounts.User, type: :id

    has_many :events, Blackboex.FlowConversations.FlowEvent, foreign_key: :run_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :conversation_id,
      :flow_id,
      :organization_id,
      :user_id,
      :run_type,
      :status,
      :trigger_message,
      :definition_before
    ])
    |> validate_required([
      :conversation_id,
      :flow_id,
      :organization_id,
      :user_id,
      :run_type
    ])
    |> validate_inclusion(:run_type, @valid_run_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:trigger_message, max: @max_message_chars)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:flow_id)
  end

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
      :definition_after,
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

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
