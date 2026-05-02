defmodule Blackboex.Repo.Migrations.AddSampleManifestFields do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :sample_workspace, :boolean, null: false, default: false
      add :sample_manifest_version, :string
      add :sample_synced_at, :utc_datetime
    end

    create index(:projects, [:sample_workspace])

    alter table(:apis) do
      add :sample_uuid, :uuid
      add :sample_manifest_version, :string
    end

    create unique_index(:apis, [:project_id, :sample_uuid],
             where: "sample_uuid IS NOT NULL",
             name: :apis_project_id_sample_uuid_index
           )

    alter table(:flows) do
      add :sample_uuid, :uuid
      add :sample_manifest_version, :string
    end

    create unique_index(:flows, [:project_id, :sample_uuid],
             where: "sample_uuid IS NOT NULL",
             name: :flows_project_id_sample_uuid_index
           )

    alter table(:pages) do
      add :sample_uuid, :uuid
      add :sample_manifest_version, :string
    end

    create unique_index(:pages, [:project_id, :sample_uuid],
             where: "sample_uuid IS NOT NULL",
             name: :pages_project_id_sample_uuid_index
           )

    alter table(:playgrounds) do
      add :sample_uuid, :uuid
      add :sample_manifest_version, :string
    end

    create unique_index(:playgrounds, [:project_id, :sample_uuid],
             where: "sample_uuid IS NOT NULL",
             name: :playgrounds_project_id_sample_uuid_index
           )
  end
end
