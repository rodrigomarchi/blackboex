defmodule Blackboex.Repo.Migrations.CreateFlows do
  use Ecto.Migration

  def change do
    create table(:flows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "draft"
      add :definition, :map, default: %{}

      timestamps()
    end

    create unique_index(:flows, [:organization_id, :slug])
    create index(:flows, [:user_id])
    create index(:flows, [:status])
  end
end
