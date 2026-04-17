defmodule Blackboex.Repo.Migrations.CreatePlaygroundConversations do
  use Ecto.Migration

  def change do
    create table(:playground_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :playground_id, references(:playgrounds, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :total_runs, :integer, null: false, default: 0
      add :total_events, :integer, null: false, default: 0
      add :total_input_tokens, :integer, null: false, default: 0
      add :total_output_tokens, :integer, null: false, default: 0
      add :total_cost_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:playground_conversations, [:playground_id])
    create index(:playground_conversations, [:organization_id])
    create index(:playground_conversations, [:project_id])

    create table(:playground_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:playground_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :playground_id, references(:playgrounds, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :nilify_all), null: false

      add :run_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :trigger_message, :text
      add :code_before, :text
      add :code_after, :text
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

    create index(:playground_runs, [:conversation_id])
    create index(:playground_runs, [:playground_id, :inserted_at])
    create index(:playground_runs, [:status, :updated_at])
    create index(:playground_runs, [:organization_id])

    create table(:playground_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:playground_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :content, :text
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:playground_events, [:run_id, :sequence])
    create index(:playground_events, [:event_type])
  end
end
