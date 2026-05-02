defmodule Blackboex.Repo.Migrations.CreateInstanceSettings do
  use Ecto.Migration

  def change do
    create table(:instance_settings, primary_key: false) do
      add :id, :integer, primary_key: true
      add :app_name, :string, null: false
      add :public_url, :string, null: false
      add :setup_completed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    execute(
      "ALTER TABLE instance_settings ADD CONSTRAINT instance_settings_singleton CHECK (id = 1)",
      "ALTER TABLE instance_settings DROP CONSTRAINT instance_settings_singleton"
    )
  end
end
