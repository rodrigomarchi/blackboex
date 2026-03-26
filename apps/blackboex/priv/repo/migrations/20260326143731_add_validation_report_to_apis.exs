defmodule Blackboex.Repo.Migrations.AddValidationReportToApis do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :validation_report, :map
    end
  end
end
