defmodule Blackboex.Conversations.Run do
  @moduledoc """
  Schema for agent runs. Each run represents a single execution of the agent,
  triggered by a user message (generation, edit, test, doc generation, etc.).

  A run tracks the full lifecycle: config, cost, timing, final artifacts,
  and a human-readable summary for context in future runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_run_types ~w(generation edit test_only doc_only)
  @valid_statuses ~w(pending running completed failed cancelled partial)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :run_type, :string
    field :status, :string, default: "pending"
    field :trigger_message, :string

    field :config, :map, default: %{}

    field :final_code, :string
    field :final_test_code, :string
    field :final_doc, :string
    field :error_summary, :string
    field :run_summary, :string

    field :iteration_count, :integer, default: 0
    field :event_count, :integer, default: 0
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0

    field :model, :string
    field :fallback_model, :string

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer

    belongs_to :conversation, Blackboex.Conversations.Conversation
    belongs_to :api, Blackboex.Apis.Api
    belongs_to :user, Blackboex.Accounts.User, type: :id
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :api_version, Blackboex.Apis.ApiVersion

    has_many :events, Blackboex.Conversations.Event

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :conversation_id,
      :api_id,
      :user_id,
      :organization_id,
      :run_type,
      :status,
      :trigger_message,
      :config
    ])
    |> validate_required([:conversation_id, :api_id, :user_id, :organization_id, :run_type])
    |> validate_inclusion(:run_type, @valid_run_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:api_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)

  @spec completion_changeset(t(), map()) :: Ecto.Changeset.t()
  def completion_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :final_code,
      :final_test_code,
      :final_doc,
      :error_summary,
      :run_summary,
      :completed_at,
      :duration_ms,
      :api_version_id
    ])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @spec metrics_changeset(t(), map()) :: Ecto.Changeset.t()
  def metrics_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :iteration_count,
      :event_count,
      :input_tokens,
      :output_tokens,
      :cost_cents,
      :model,
      :fallback_model,
      :started_at
    ])
  end

  @spec valid_run_types() :: [String.t()]
  def valid_run_types, do: @valid_run_types

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses
end
