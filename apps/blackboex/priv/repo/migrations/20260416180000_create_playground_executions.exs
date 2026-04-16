defmodule Blackboex.Repo.Migrations.CreatePlaygroundExecutions do
  use Ecto.Migration

  def change do
    create table(:playground_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :playground_id, references(:playgrounds, type: :binary_id, on_delete: :delete_all),
        null: false

      add :run_number, :integer, null: false
      add :code_snapshot, :text, null: false
      add :output, :text
      add :status, :string, null: false, default: "running"
      add :duration_ms, :integer

      timestamps()
    end

    create index(:playground_executions, [:playground_id, :inserted_at])
    create unique_index(:playground_executions, [:playground_id, :run_number])
  end
end
