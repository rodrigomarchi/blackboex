defmodule Blackboex.Repo.Migrations.CreateApiData do
  use Ecto.Migration

  def change do
    create table(:api_data, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :value, :jsonb, null: false

      timestamps()
    end

    create unique_index(:api_data, [:api_id, :key])
    create index(:api_data, [:api_id])
  end
end
