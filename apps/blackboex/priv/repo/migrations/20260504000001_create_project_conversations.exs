defmodule Blackboex.Repo.Migrations.CreateProjectConversations do
  use Ecto.Migration

  def change do
    create table(:project_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "active"
      add :archived_at, :utc_datetime_usec

      add :total_runs, :integer, null: false, default: 0
      add :total_events, :integer, null: false, default: 0
      add :total_input_tokens, :integer, null: false, default: 0
      add :total_output_tokens, :integer, null: false, default: 0
      add :total_cost_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:project_conversations, [:project_id],
             where: "status = 'active'",
             name: :project_conversations_unique_active
           )

    create index(:project_conversations, [:organization_id])
    create index(:project_conversations, [:project_id, :inserted_at])
  end
end
