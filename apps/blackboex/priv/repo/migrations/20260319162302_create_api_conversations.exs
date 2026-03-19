defmodule Blackboex.Repo.Migrations.CreateApiConversations do
  use Ecto.Migration

  def change do
    create table(:api_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :messages, :jsonb, default: "[]"
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create unique_index(:api_conversations, [:api_id])
  end
end
