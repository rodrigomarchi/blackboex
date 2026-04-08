defmodule Blackboex.Repo.Migrations.AddTemplateIdToApis do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :template_id, :string, null: true
    end
  end
end
