defmodule Blackboex.Repo.Migrations.CreateProjectRuns do
  use Ecto.Migration

  def change do
    create table(:project_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:project_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :nothing), null: false

      add :run_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :trigger_message, :text
      add :run_summary, :text
      add :error_message, :text

      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_cents, :integer, null: false, default: 0
      add :duration_ms, :integer

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps()
    end

    create index(:project_runs, [:conversation_id])
    create index(:project_runs, [:project_id, :inserted_at])
    create index(:project_runs, [:status, :updated_at])
    create index(:project_runs, [:organization_id])
    create index(:project_runs, [:user_id])
  end
end
