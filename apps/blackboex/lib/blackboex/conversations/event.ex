defmodule Blackboex.Conversations.Event do
  @moduledoc """
  Schema for agent events. Each event is an atomic action within a run:
  a message, tool call, tool result, code snapshot, guardrail trigger, etc.

  Events are stored as individual rows (not JSONB blobs) for full queryability.
  The `sequence` field preserves chronological order within a run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_event_types ~w(
    user_message
    system_message
    assistant_message
    tool_call
    tool_result
    code_snapshot
    guardrail_trigger
    error
    status_change
  )

  @valid_roles ~w(user assistant system tool)

  @valid_tool_names ~w(
    generate_code
    compile_code
    format_code
    lint_code
    generate_tests
    run_tests
    submit_code
  )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :event_type, :string
    field :sequence, :integer

    field :role, :string
    field :content, :string

    field :tool_name, :string
    field :tool_input, :map
    field :tool_output, :map
    field :tool_success, :boolean
    field :tool_duration_ms, :integer

    field :code_snapshot, :string
    field :test_snapshot, :string

    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cost_cents, :integer

    field :metadata, :map, default: %{}

    belongs_to :run, Blackboex.Conversations.Run
    belongs_to :conversation, Blackboex.Conversations.Conversation

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :run_id,
      :conversation_id,
      :event_type,
      :sequence,
      :role,
      :content,
      :tool_name,
      :tool_input,
      :tool_output,
      :tool_success,
      :tool_duration_ms,
      :code_snapshot,
      :test_snapshot,
      :input_tokens,
      :output_tokens,
      :cost_cents,
      :metadata
    ])
    |> validate_required([:run_id, :conversation_id, :event_type, :sequence])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_role()
    |> validate_tool_fields()
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:conversation_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)

  @spec valid_event_types() :: [String.t()]
  def valid_event_types, do: @valid_event_types

  @spec valid_tool_names() :: [String.t()]
  def valid_tool_names, do: @valid_tool_names

  defp validate_role(changeset) do
    case get_change(changeset, :role) do
      nil -> changeset
      role when role in @valid_roles -> changeset
      _ -> add_error(changeset, :role, "must be one of: #{Enum.join(@valid_roles, ", ")}")
    end
  end

  defp validate_tool_fields(changeset) do
    event_type = get_field(changeset, :event_type)

    if event_type in ["tool_call", "tool_result"] do
      changeset
      |> validate_required([:tool_name])
      |> validate_tool_name()
    else
      changeset
    end
  end

  defp validate_tool_name(changeset) do
    case get_change(changeset, :tool_name) do
      nil ->
        changeset

      name when name in @valid_tool_names ->
        changeset

      _ ->
        add_error(changeset, :tool_name, "must be one of: #{Enum.join(@valid_tool_names, ", ")}")
    end
  end
end
