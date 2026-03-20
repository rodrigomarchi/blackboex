defmodule Blackboex.Repo.Migrations.CreateProcessedStripeEvents do
  use Ecto.Migration

  def change do
    create table(:processed_stripe_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, :string, null: false
      add :event_type, :string, null: false
      add :processed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:processed_stripe_events, [:event_id])
  end
end
