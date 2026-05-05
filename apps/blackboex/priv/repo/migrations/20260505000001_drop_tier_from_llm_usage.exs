defmodule Blackboex.Repo.Migrations.DropTierFromLlmUsage do
  @moduledoc """
  Drops the `tier` column from `llm_usage`. Was added by
  `20260504000006_add_tier_to_llm_usage.exs` for the (since-removed)
  three-tier model routing in the Project Agent feature. The whole
  per-tier infra (planner/executor/navigation) was overengineering for a
  single-tenant dev platform; everything that depended on it was
  removed, so this column is now dead weight.
  """
  use Ecto.Migration

  def change do
    alter table(:llm_usage) do
      remove :tier, :string, null: false, default: "executor"
    end
  end
end
