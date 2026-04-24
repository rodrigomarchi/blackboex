defmodule Blackboex.Repo.Migrations.RenameFlowSecretsToProjectEnvVars do
  use Ecto.Migration

  @old_entity_schema "Elixir.Blackboex.FlowSecrets.FlowSecret"
  @new_entity_schema "Elixir.Blackboex.ProjectEnvVars.ProjectEnvVar"

  def up do
    # 1) Rename the table
    rename table(:flow_secrets), to: table(:project_env_vars)

    # 2) Add the `kind` column with a safe default so existing rows become env vars
    alter table(:project_env_vars) do
      add :kind, :string, null: false, default: "env"
    end

    # 3) Constrain `kind` to the supported enum values at the DB level
    create constraint(:project_env_vars, :kind_must_be_valid,
             check: "kind IN ('env', 'llm_anthropic')"
           )

    # 4) Drop the old project-scoped unique index; replace with one that includes kind
    drop_if_exists unique_index(:flow_secrets, [:project_id, :name])
    drop_if_exists unique_index(:project_env_vars, [:project_id, :name])

    create unique_index(:project_env_vars, [:project_id, :kind, :name])

    # 5) Ensure at most one LLM Anthropic key per project via partial unique index
    create unique_index(:project_env_vars, [:project_id, :kind],
             where: "kind = 'llm_anthropic'",
             name: :project_env_vars_unique_llm_per_project_idx
           )

    # 6) ExAudit data migration: rewrite legacy entity_schema references in `versions`.
    # The `versions` table is created/managed by ex_audit; its schema module refs
    # live in `entity_schema` (see `Blackboex.Audit.Version`). FlowSecret was not
    # in the tracked_schemas list historically, so this UPDATE is typically a
    # no-op, but is included for forward safety if it ever was tracked.
    execute(
      "UPDATE versions SET entity_schema = '#{@new_entity_schema}' WHERE entity_schema = '#{@old_entity_schema}'"
    )
  end

  def down do
    # Reverse the ExAudit data migration first
    execute(
      "UPDATE versions SET entity_schema = '#{@old_entity_schema}' WHERE entity_schema = '#{@new_entity_schema}'"
    )

    # Drop the new indexes / constraints introduced above
    drop_if_exists unique_index(:project_env_vars, [:project_id, :kind],
                     name: :project_env_vars_unique_llm_per_project_idx
                   )

    drop_if_exists unique_index(:project_env_vars, [:project_id, :kind, :name])

    drop_if_exists constraint(:project_env_vars, :kind_must_be_valid)

    # Remove the kind column so schema matches the original flow_secrets shape
    alter table(:project_env_vars) do
      remove :kind
    end

    # Recreate the legacy unique index
    create unique_index(:project_env_vars, [:project_id, :name])

    # Rename back to flow_secrets
    rename table(:project_env_vars), to: table(:flow_secrets)
  end
end
