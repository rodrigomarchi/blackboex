defmodule Blackboex.Repo.Migrations.AddTestCodeToApisAndVersions do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :test_code, :text
    end

    alter table(:api_versions) do
      add :test_code, :text
    end
  end
end
