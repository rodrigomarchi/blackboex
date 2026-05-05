defmodule Blackboex.Repo.Migrations.CreatePlanTasks do
  use Ecto.Migration

  def change do
    create table(:plan_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plan_id, references(:plans, type: :binary_id, on_delete: :delete_all), null: false

      add :order, :integer, null: false
      add :artifact_type, :string, null: false
      # "api" | "flow" | "page" | "playground"
      add :action, :string, null: false
      # "create" | "edit"
      add :target_artifact_id, :binary_id
      # nil for :create

      add :title, :string, null: false
      add :params, :map, null: false, default: %{}
      add :acceptance_criteria, {:array, :string}, default: []

      add :status, :string, null: false, default: "pending"
      # :pending | :running | :done | :failed | :skipped (creation-time-only)

      # child_run_id references the *child artifact's* Run table; we use a
      # polymorphic approach: store the child run id (binary_id) without an FK
      # constraint. Reverse lookup is via the matching artifact context.
      add :child_run_id, :binary_id

      add :error_message, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plan_tasks, [:plan_id, :order])
    create index(:plan_tasks, [:plan_id, :status])
    create index(:plan_tasks, [:child_run_id])
  end
end
