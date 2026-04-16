defmodule Blackboex.Repo.Migrations.AddLastVisitedToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_organization_id,
          references(:organizations, type: :binary_id, on_delete: :nilify_all)

      add :last_project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:users, [:last_organization_id])
    create index(:users, [:last_project_id])
  end
end
