defmodule Blackboex.Repo.Migrations.FixPageRunsUserFk do
  use Ecto.Migration

  # The original create migration set `user_id` as `null: false` with
  # `on_delete: :nilify_all`. Those two are mutually incompatible: when a user
  # is deleted Postgres tries to set `user_id` NULL, which violates NOT NULL
  # and rolls back the user deletion. Switch to `:nothing` so user deletes
  # surface as foreign-key errors rather than silently succeeding/failing.

  def up do
    drop constraint(:page_runs, "page_runs_user_id_fkey")

    alter table(:page_runs) do
      modify :user_id, references(:users, on_delete: :nothing), null: false
    end
  end

  def down do
    drop constraint(:page_runs, "page_runs_user_id_fkey")

    alter table(:page_runs) do
      modify :user_id, references(:users, on_delete: :nilify_all), null: false
    end
  end
end
