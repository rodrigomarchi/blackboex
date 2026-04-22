defmodule Blackboex.Repo.Migrations.CreateFlowConversations do
  use Ecto.Migration

  def change do
    create table(:flow_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false

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

    create unique_index(:flow_conversations, [:flow_id],
             where: "status = 'active'",
             name: :flow_conversations_unique_active
           )

    create index(:flow_conversations, [:organization_id])
    create index(:flow_conversations, [:project_id])
    create index(:flow_conversations, [:flow_id, :inserted_at])

    create table(:flow_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:flow_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :flow_id, references(:flows, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :nothing), null: false

      add :run_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :trigger_message, :text
      add :definition_before, :map, null: false, default: %{}
      add :definition_after, :map
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

    create index(:flow_runs, [:conversation_id])
    create index(:flow_runs, [:flow_id, :inserted_at])
    create index(:flow_runs, [:status, :updated_at])
    create index(:flow_runs, [:organization_id])

    create table(:flow_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:flow_runs, type: :binary_id, on_delete: :delete_all), null: false

      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :content, :text
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:flow_events, [:run_id, :sequence])
    create index(:flow_events, [:event_type])
  end
end
