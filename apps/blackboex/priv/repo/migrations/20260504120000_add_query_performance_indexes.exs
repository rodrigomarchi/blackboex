defmodule Blackboex.Repo.Migrations.AddQueryPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Missing leading indexes for foreign keys.
    create_if_not_exists index(:apis, [:organization_id, :inserted_at])
    create_if_not_exists index(:conversations, [:api_id])
    create_if_not_exists index(:flows, [:organization_id, :inserted_at])
    create_if_not_exists index(:pages, [:parent_id, :position])
    create_if_not_exists index(:project_env_vars, [:organization_id])

    # Project/org-scoped listings in LiveView sidebars and dashboards.
    create_if_not_exists index(:apis, [:project_id, :inserted_at])
    create_if_not_exists index(:apis, [:project_id, :name])

    create_if_not_exists index(:flows, [:project_id, :inserted_at])
    create_if_not_exists index(:flows, [:project_id, :name])

    create_if_not_exists index(:pages, [:organization_id, :updated_at])
    create_if_not_exists index(:pages, [:project_id, :updated_at])

    create_if_not_exists index(:playgrounds, [:organization_id, :updated_at])
    create_if_not_exists index(:playgrounds, [:project_id, :updated_at])
    create_if_not_exists index(:playgrounds, [:project_id, :name])

    # Dashboard time-window aggregations and recent-activity queries.
    create_if_not_exists index(:invocation_logs, [:project_id, :inserted_at])
    create_if_not_exists index(:flow_executions, [:organization_id, :inserted_at])
    create_if_not_exists index(:flow_executions, [:project_id, :inserted_at])
    create_if_not_exists index(:llm_usage, [:organization_id, :inserted_at])
    create_if_not_exists index(:llm_usage, [:project_id, :inserted_at])
    create_if_not_exists index(:runs, [:organization_id, :inserted_at])
  end
end
