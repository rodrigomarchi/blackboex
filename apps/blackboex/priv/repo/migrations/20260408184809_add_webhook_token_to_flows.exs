defmodule Blackboex.Repo.Migrations.AddWebhookTokenToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :webhook_token, :string, null: false
    end

    create unique_index(:flows, [:webhook_token])
  end
end
