defmodule Blackboex.Billing.ProcessedEvent do
  @moduledoc """
  Schema for tracking processed Stripe webhook events.
  Used for idempotent event processing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "processed_stripe_events" do
    field :event_id, :string
    field :event_type, :string
    field :processed_at, :utc_datetime

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_id, :event_type, :processed_at])
    |> validate_required([:event_id, :event_type, :processed_at])
    |> validate_length(:event_id, max: 255)
    |> validate_length(:event_type, max: 255)
    |> unique_constraint(:event_id)
  end
end
