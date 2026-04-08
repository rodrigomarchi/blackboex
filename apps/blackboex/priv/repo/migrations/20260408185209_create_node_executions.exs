defmodule Blackboex.Repo.Migrations.CreateNodeExecutions do
  use Ecto.Migration

  def change do
    create table(:node_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :flow_execution_id,
          references(:flow_executions, type: :binary_id, on_delete: :delete_all), null: false

      add :node_id, :string, null: false
      add :node_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :input, :map
      add :output, :map
      add :error, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :duration_ms, :integer

      timestamps()
    end

    create unique_index(:node_executions, [:flow_execution_id, :node_id])
  end
end
