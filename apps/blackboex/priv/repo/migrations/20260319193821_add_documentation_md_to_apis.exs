defmodule Blackboex.Repo.Migrations.AddDocumentationMdToApis do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :documentation_md, :text
    end
  end
end
