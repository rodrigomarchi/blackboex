defmodule Blackboex.Repo.Migrations.AddMissingFkIndexes do
  use Ecto.Migration

  # Foreign-key columns without an index force Postgres to do a sequential scan
  # on the child table whenever the parent row is deleted (or whenever a join
  # filters by the FK). Add covering indexes for every FK that was previously
  # uncovered.
  #
  # Detected via static scan of the migration history (see commit message).
  def change do
    create_if_not_exists index(:api_file_revisions, [:created_by_id])
    create_if_not_exists index(:api_versions, [:created_by_id])
    create_if_not_exists index(:flow_runs, [:user_id])
    create_if_not_exists index(:invocation_logs, [:api_key_id])
    create_if_not_exists index(:llm_usage, [:api_id])
    create_if_not_exists index(:org_invitations, [:invited_by_id])
    create_if_not_exists index(:page_runs, [:user_id])
    create_if_not_exists index(:playground_runs, [:user_id])
    create_if_not_exists index(:runs, [:api_version_id])
    create_if_not_exists index(:runs, [:user_id])
  end
end
