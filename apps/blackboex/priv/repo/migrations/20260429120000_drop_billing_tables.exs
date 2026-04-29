defmodule Blackboex.Repo.Migrations.DropBillingTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:usage_events)
    drop_if_exists table(:daily_usage)
    drop_if_exists table(:processed_stripe_events)
    drop_if_exists table(:subscriptions)
  end

  def down do
    raise "Billing tables removal is irreversible — restore from backup if needed"
  end
end
