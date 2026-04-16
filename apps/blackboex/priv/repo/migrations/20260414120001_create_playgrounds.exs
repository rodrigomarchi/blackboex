defmodule Blackboex.Repo.Migrations.CreatePlaygrounds do
  use Ecto.Migration

  def change do
    create table(:playgrounds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :code, :text, default: ""
      add :last_output, :text

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:playgrounds, [:project_id, :slug])
    create index(:playgrounds, [:organization_id])
    create index(:playgrounds, [:user_id])
  end
end
