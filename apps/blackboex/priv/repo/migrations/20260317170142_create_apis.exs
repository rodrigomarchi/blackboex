defmodule Blackboex.Repo.Migrations.CreateApis do
  use Ecto.Migration

  def change do
    create table(:apis, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :source_code, :text
      add :template_type, :string, null: false, default: "computation"
      add :status, :string, null: false, default: "draft"
      add :method, :string, null: false, default: "POST"
      add :param_schema, :map
      add :example_request, :map
      add :example_response, :map

      timestamps()
    end

    create unique_index(:apis, [:organization_id, :slug])
    create index(:apis, [:user_id])
    create index(:apis, [:status])
  end
end
