defmodule Blackboex.PageConversations.PageEvent do
  @moduledoc """
  Atomic event within a `PageRun`. Each row captures one chat message,
  content delta, or terminal signal in the conversation timeline.
  `sequence` is unique per run and preserves chronological order.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_event_types ~w(user_message assistant_message content_delta completed failed)

  @max_content_bytes 1_048_576

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_events" do
    field :sequence, :integer
    field :event_type, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :run, Blackboex.PageConversations.PageRun

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:run_id, :sequence, :event_type, :content, :metadata])
    |> validate_required([:run_id, :sequence, :event_type])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_length(:content, max: @max_content_bytes)
    |> unique_constraint([:run_id, :sequence])
    |> foreign_key_constraint(:run_id)
  end

  @spec valid_event_types() :: [String.t()]
  def valid_event_types, do: @valid_event_types

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
