defmodule Blackboex.Repo.Migrations.CreatePageConversations do
  use Ecto.Migration

  def change do
    create table(:page_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :page_id, references(:pages, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
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

    create unique_index(:page_conversations, [:page_id],
             where: "status = 'active'",
             name: :page_conversations_unique_active
           )

    create index(:page_conversations, [:organization_id])
    create index(:page_conversations, [:project_id])
    create index(:page_conversations, [:page_id, :inserted_at])

    create table(:page_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:page_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :page_id, references(:pages, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      # nilify_all conflicts with null: false; use :nothing so user deletion
      # is blocked while runs exist (audit trail intact). Cleanup happens via
      # cascade from page deletion or manual archival workflows.
      add :user_id, references(:users, on_delete: :nothing), null: false

      add :run_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :trigger_message, :text
      add :content_before, :text
      add :content_after, :text
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

    create index(:page_runs, [:conversation_id])
    create index(:page_runs, [:page_id, :inserted_at])
    create index(:page_runs, [:status, :updated_at])
    create index(:page_runs, [:organization_id])

    create table(:page_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:page_runs, type: :binary_id, on_delete: :delete_all), null: false

      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :content, :text
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:page_events, [:run_id, :sequence])
    create index(:page_events, [:event_type])
  end
end
