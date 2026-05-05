defmodule Blackboex.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      # FK to project_runs (the new sibling table), NOT to runs.
      add :run_id, references(:project_runs, type: :binary_id, on_delete: :nilify_all)

      add :parent_plan_id, references(:plans, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "draft"
      # :draft | :approved | :running | :done | :partial | :failed

      add :title, :string, null: false
      add :user_message, :text, null: false
      add :markdown_body, :text, null: false
      add :model_tier_caps, :map, null: false, default: %{}

      add :approved_by_user_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :utc_datetime_usec
      add :failure_reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:plans, [:project_id, :status])
    create index(:plans, [:run_id])
    create index(:plans, [:parent_plan_id])
    create index(:plans, [:approved_by_user_id])

    create unique_index(:plans, [:project_id],
             name: :plans_one_active_per_project_idx,
             where: "status IN ('approved','running')"
           )
  end
end
