defmodule Blackboex.Repo.Migrations.AddHierarchyToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :parent_id, references(:pages, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer, null: false, default: 0
    end

    create index(:pages, [:project_id, :parent_id, :position])
  end
end
