defmodule Blackboex.Repo.Migrations.AddPartialUniqueIndexDailyUsageOrgLevel do
  use Ecto.Migration

  def change do
    # Partial unique index for org-level rollup rows (project_id IS NULL).
    # Required for ON CONFLICT conflict-target resolution since PostgreSQL
    # treats NULLs as distinct in regular unique indexes.
    create unique_index(:daily_usage, [:organization_id, :date],
             where: "project_id IS NULL",
             name: :daily_usage_org_level_unique_index
           )
  end
end
