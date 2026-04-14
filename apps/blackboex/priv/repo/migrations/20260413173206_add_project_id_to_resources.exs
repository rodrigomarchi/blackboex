defmodule Blackboex.Repo.Migrations.AddProjectIdToResources do
  use Ecto.Migration

  def change do
    # APIs - NOT NULL, unique constraint changes from org to project scope
    alter table(:apis) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    drop unique_index(:apis, [:organization_id, :slug])
    create unique_index(:apis, [:project_id, :slug])
    create index(:apis, [:project_id])

    # API Keys - NOT NULL
    alter table(:api_keys) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:api_keys, [:project_id])

    # Flows - NOT NULL, unique constraint changes from org to project scope
    alter table(:flows) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    drop unique_index(:flows, [:organization_id, :slug])
    create unique_index(:flows, [:project_id, :slug])
    create index(:flows, [:project_id])

    # Flow Secrets - NOT NULL, unique constraint changes from org to project scope
    alter table(:flow_secrets) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    drop unique_index(:flow_secrets, [:organization_id, :name])
    create unique_index(:flow_secrets, [:project_id, :name])
    create index(:flow_secrets, [:project_id])

    # Flow Executions - NOT NULL
    alter table(:flow_executions) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:flow_executions, [:project_id])

    # Conversations - NOT NULL, unique constraint changes from org to project scope
    alter table(:conversations) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    drop unique_index(:conversations, [:organization_id, :api_id])
    create unique_index(:conversations, [:project_id, :api_id])
    create index(:conversations, [:project_id])

    # Runs - NOT NULL
    alter table(:runs) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:runs, [:project_id])

    # Usage Events - nullable (some are org-level)
    alter table(:usage_events) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:usage_events, [:project_id])

    # Daily Usage - nullable (nil = org-level aggregate), unique changes
    alter table(:daily_usage) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    drop unique_index(:daily_usage, [:organization_id, :date])
    create unique_index(:daily_usage, [:organization_id, :project_id, :date])
    create index(:daily_usage, [:project_id])

    # LLM Usage - NOT NULL
    alter table(:llm_usage) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:llm_usage, [:project_id])

    # Audit Logs - nullable
    alter table(:audit_logs) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:audit_logs, [:project_id])

    # Invocation Logs - NOT NULL
    alter table(:invocation_logs) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:invocation_logs, [:project_id])

    # Test Suites - NOT NULL
    alter table(:test_suites) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:test_suites, [:project_id])
  end
end
