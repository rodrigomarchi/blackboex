defmodule Blackboex.Repo.Migrations.AddTierToLlmUsage do
  use Ecto.Migration

  def change do
    alter table(:llm_usage) do
      add :tier, :string, null: false, default: "executor"
    end
  end
end
