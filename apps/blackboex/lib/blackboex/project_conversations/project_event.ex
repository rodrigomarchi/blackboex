defmodule Blackboex.ProjectConversations.ProjectEvent do
  @moduledoc """
  Atomic event within a `ProjectRun`. Each row captures one chat message,
  a planning artifact reference, or a terminal signal in the conversation
  timeline. `sequence` is unique per run and preserves chronological order.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_event_types ~w(user_message assistant_message plan_drafted plan_approved task_dispatched task_completed task_failed completed failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_events" do
    field :sequence, :integer
    field :event_type, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :run, Blackboex.ProjectConversations.ProjectRun

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:run_id, :sequence, :event_type, :content, :metadata])
    |> validate_required([:run_id, :sequence, :event_type])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_id, :sequence])
    |> foreign_key_constraint(:run_id)
  end

  @spec valid_event_types() :: [String.t()]
  def valid_event_types, do: @valid_event_types

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
