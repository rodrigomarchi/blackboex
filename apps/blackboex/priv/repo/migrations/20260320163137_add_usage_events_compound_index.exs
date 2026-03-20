defmodule Blackboex.Repo.Migrations.AddUsageEventsCompoundIndex do
  use Ecto.Migration

  def change do
    create index(:usage_events, [:organization_id, :event_type, :inserted_at])
  end
end
