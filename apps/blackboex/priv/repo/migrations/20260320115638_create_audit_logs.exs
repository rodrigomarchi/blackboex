defmodule Blackboex.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :nilify_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :metadata, :map, default: %{}
      add :ip_address, :string

      timestamps(updated_at: false)
    end

    create index(:audit_logs, [:organization_id, :inserted_at])
    create index(:audit_logs, [:user_id, :inserted_at])
    create index(:audit_logs, [:action])
  end
end
