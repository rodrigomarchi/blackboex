defmodule Blackboex.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string
      add :status, :string, null: false, default: "active"

      add :total_runs, :integer, null: false, default: 0
      add :total_events, :integer, null: false, default: 0
      add :total_input_tokens, :integer, null: false, default: 0
      add :total_output_tokens, :integer, null: false, default: 0
      add :total_cost_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:conversations, [:api_id])
    create index(:conversations, [:organization_id])

    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :run_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :trigger_message, :text

      add :config, :map, null: false, default: %{}

      add :final_code, :text
      add :final_test_code, :text
      add :final_doc, :text
      add :error_summary, :text
      add :run_summary, :text

      add :iteration_count, :integer, null: false, default: 0
      add :event_count, :integer, null: false, default: 0
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_cents, :integer, null: false, default: 0

      add :model, :string
      add :fallback_model, :string

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      add :api_version_id, references(:api_versions, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:runs, [:conversation_id])
    create index(:runs, [:api_id])
    create index(:runs, [:organization_id, :run_type])
    create index(:runs, [:status, :updated_at])

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false
      add :sequence, :integer, null: false

      add :role, :string
      add :content, :text

      add :tool_name, :string
      add :tool_input, :map
      add :tool_output, :map
      add :tool_success, :boolean
      add :tool_duration_ms, :integer

      add :code_snapshot, :text
      add :test_snapshot, :text

      add :input_tokens, :integer
      add :output_tokens, :integer
      add :cost_cents, :integer

      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:events, [:run_id, :sequence])
    create index(:events, [:conversation_id])
    create index(:events, [:event_type])
    create index(:events, [:tool_name], where: "tool_name IS NOT NULL")
  end
end
