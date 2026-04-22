defmodule Blackboex.FlowConversations.FlowEvent do
  @moduledoc """
  Atomic event within a `FlowRun`. Each row captures one chat message,
  definition delta, or terminal signal in the conversation timeline.

  The `sequence` field preserves chronological order within a run and is
  unique per run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_event_types ~w(user_message assistant_message definition_delta completed failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flow_events" do
    field :sequence, :integer
    field :event_type, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :run, Blackboex.FlowConversations.FlowRun

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:run_id, :sequence, :event_type, :content, :metadata])
    |> validate_required([:run_id, :sequence, :event_type])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> unique_constraint([:run_id, :sequence])
    |> foreign_key_constraint(:run_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)

  @spec valid_event_types() :: [String.t()]
  def valid_event_types, do: @valid_event_types
end
