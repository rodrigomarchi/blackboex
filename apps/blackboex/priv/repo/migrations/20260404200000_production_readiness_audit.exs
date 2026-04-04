defmodule Blackboex.Repo.Migrations.ProductionReadinessAudit do
  use Ecto.Migration

  def up do
    # 1. Convert naive_datetime → utc_datetime_usec in users table
    alter table(:users) do
      modify :confirmed_at, :utc_datetime_usec, from: :naive_datetime
      modify :inserted_at, :utc_datetime_usec, from: :naive_datetime
      modify :updated_at, :utc_datetime_usec, from: :naive_datetime
    end

    # 2. Convert naive_datetime → utc_datetime_usec in users_tokens table
    alter table(:users_tokens) do
      modify :authenticated_at, :utc_datetime_usec, from: :naive_datetime
      modify :inserted_at, :utc_datetime_usec, from: :naive_datetime
    end

    # 3. Convert utc_datetime → utc_datetime_usec in api_keys
    alter table(:api_keys) do
      modify :last_used_at, :utc_datetime_usec, from: :utc_datetime
      modify :expires_at, :utc_datetime_usec, from: :utc_datetime
      modify :revoked_at, :utc_datetime_usec, from: :utc_datetime
    end

    # 4. Replace api_id-only unique index on conversations with [:organization_id, :api_id]
    drop_if_exists unique_index(:conversations, [:api_id])
    create unique_index(:conversations, [:organization_id, :api_id])

    # 5. Add unique index on test_suites [:api_id, :version_number]
    create unique_index(:test_suites, [:api_id, :version_number])

    # 6. Add partial index on api_keys for active (non-revoked) key prefixes
    create index(:api_keys, [:key_prefix],
             where: "revoked_at IS NULL",
             name: :api_keys_active_prefix_index
           )
  end

  def down do
    drop_if_exists index(:api_keys, [:key_prefix], name: :api_keys_active_prefix_index)
    drop_if_exists unique_index(:test_suites, [:api_id, :version_number])
    drop_if_exists unique_index(:conversations, [:organization_id, :api_id])
    create unique_index(:conversations, [:api_id])

    alter table(:api_keys) do
      modify :last_used_at, :utc_datetime, from: :utc_datetime_usec
      modify :expires_at, :utc_datetime, from: :utc_datetime_usec
      modify :revoked_at, :utc_datetime, from: :utc_datetime_usec
    end

    alter table(:users_tokens) do
      modify :inserted_at, :naive_datetime, from: :utc_datetime_usec
      modify :authenticated_at, :naive_datetime, from: :utc_datetime_usec
    end

    alter table(:users) do
      modify :updated_at, :naive_datetime, from: :utc_datetime_usec
      modify :inserted_at, :naive_datetime, from: :utc_datetime_usec
      modify :confirmed_at, :naive_datetime, from: :utc_datetime_usec
    end
  end
end
