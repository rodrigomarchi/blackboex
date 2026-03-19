defmodule Blackboex.Repo.Migrations.AddPublishingFieldsToApis do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      add :visibility, :string, null: false, default: "private"
      add :requires_auth, :boolean, null: false, default: true
    end
  end
end
