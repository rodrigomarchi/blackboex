defmodule Blackboex.Repo.Migrations.CreateProjectEvents do
  use Ecto.Migration

  def change do
    create table(:project_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:project_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :content, :text
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:project_events, [:run_id, :sequence])
    create index(:project_events, [:event_type])
  end
end
