defmodule Blackboex.PageConversations.PageRun do
  @moduledoc """
  Single AI editor pass on a Page. Captures the trigger message, the page
  content before/after, status, tokens and timing. Lifecycle:

      pending → running → completed | failed | canceled
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_run_types ~w(generate edit)
  @valid_statuses ~w(pending running completed failed canceled)

  @max_message_chars 10_000
  @max_content_bytes 1_048_576

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_runs" do
    field :run_type, :string
    field :status, :string, default: "pending"
    field :trigger_message, :string

    field :content_before, :string
    field :content_after, :string
    field :run_summary, :string
    field :error_message, :string

    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :duration_ms, :integer

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :conversation, Blackboex.PageConversations.PageConversation
    belongs_to :page, Blackboex.Pages.Page
    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :user, Blackboex.Accounts.User, type: :id

    has_many :events, Blackboex.PageConversations.PageEvent, foreign_key: :run_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :conversation_id,
      :page_id,
      :organization_id,
      :user_id,
      :run_type,
      :status,
      :trigger_message,
      :content_before
    ])
    |> validate_required([
      :conversation_id,
      :page_id,
      :organization_id,
      :user_id,
      :run_type
    ])
    |> validate_inclusion(:run_type, @valid_run_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:trigger_message, max: @max_message_chars)
    |> validate_length(:content_before, max: @max_content_bytes)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:page_id)
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
      :content_after,
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
    |> validate_length(:content_after, max: @max_content_bytes)
  end

  @spec valid_run_types() :: [String.t()]
  def valid_run_types, do: @valid_run_types

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
