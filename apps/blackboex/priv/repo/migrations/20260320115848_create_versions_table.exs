defmodule Blackboex.Repo.Migrations.CreateVersionsTable do
  use Ecto.Migration

  def change do
    create table(:versions) do
      # ExAudit core fields
      add :patch, :binary
      add :entity_id, :binary_id
      add :entity_schema, :string
      add :action, :string
      add :recorded_at, :utc_datetime_usec
      add :rollback, :boolean, default: false

      # Custom fields
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :ip_address, :string
    end

    create index(:versions, [:entity_id, :entity_schema])
    create index(:versions, [:actor_id])
  end
end
