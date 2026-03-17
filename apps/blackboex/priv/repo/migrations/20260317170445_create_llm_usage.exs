defmodule Blackboex.Repo.Migrations.CreateLlmUsage do
  use Ecto.Migration

  def change do
    create table(:llm_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :provider, :string, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_cents, :integer, null: false, default: 0
      add :operation, :string, null: false
      add :api_id, references(:apis, type: :binary_id, on_delete: :nilify_all)
      add :duration_ms, :integer, default: 0

      timestamps()
    end

    create index(:llm_usage, [:user_id])
    create index(:llm_usage, [:organization_id])
    create index(:llm_usage, [:inserted_at])
  end
end
