defmodule Blackboex.Repo.Migrations.CreateApiMetricRollups do
  use Ecto.Migration

  def change do
    create table(:api_metric_rollups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :hour, :integer, null: false
      add :invocations, :integer, default: 0, null: false
      add :errors, :integer, default: 0, null: false
      add :avg_duration_ms, :float, default: 0.0, null: false
      add :p95_duration_ms, :float, default: 0.0, null: false
      add :unique_consumers, :integer, default: 0, null: false

      timestamps()
    end

    create unique_index(:api_metric_rollups, [:api_id, :date, :hour])
    create index(:api_metric_rollups, [:api_id, :date])
  end
end
