defmodule Blackboex.Repo.Migrations.CreateFlowExecutions do
  use Ecto.Migration

  def change do
    create table(:flow_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "pending"
      add :input, :map, default: %{}
      add :output, :map
      add :shared_state, :map, default: %{}
      add :error, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :duration_ms, :integer

      timestamps()
    end

    create index(:flow_executions, [:flow_id, :inserted_at])
    create index(:flow_executions, [:organization_id])
    create index(:flow_executions, [:status])
  end
end
