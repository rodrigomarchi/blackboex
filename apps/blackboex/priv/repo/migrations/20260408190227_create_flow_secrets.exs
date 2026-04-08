defmodule Blackboex.Repo.Migrations.CreateFlowSecrets do
  use Ecto.Migration

  def change do
    create table(:flow_secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :encrypted_value, :binary, null: false

      timestamps()
    end

    create unique_index(:flow_secrets, [:organization_id, :name])
  end
end
