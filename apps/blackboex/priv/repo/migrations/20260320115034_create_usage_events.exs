defmodule Blackboex.Repo.Migrations.CreateUsageEvents do
  use Ecto.Migration

  def change do
    create table(:usage_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :event_type, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(updated_at: false)
    end

    create index(:usage_events, [:organization_id, :inserted_at])
    create index(:usage_events, [:event_type])
  end
end
