defmodule Blackboex.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :key_hash, :binary, null: false
      add :key_prefix, :string, null: false
      add :label, :string
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :rate_limit, :integer

      timestamps()
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:api_id])
    create index(:api_keys, [:organization_id])
  end
end
