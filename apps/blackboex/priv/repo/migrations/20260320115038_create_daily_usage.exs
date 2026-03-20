defmodule Blackboex.Repo.Migrations.CreateDailyUsage do
  use Ecto.Migration

  def change do
    create table(:daily_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :date, :date, null: false
      add :api_invocations, :integer, default: 0, null: false
      add :llm_generations, :integer, default: 0, null: false
      add :tokens_input, :integer, default: 0, null: false
      add :tokens_output, :integer, default: 0, null: false
      add :llm_cost_cents, :integer, default: 0, null: false

      timestamps()
    end

    create unique_index(:daily_usage, [:organization_id, :date])
  end
end
