defmodule Blackboex.Repo.Migrations.AddGenerationStatusToApis do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :generation_status, :string
      add :generation_error, :string
    end
  end
end
