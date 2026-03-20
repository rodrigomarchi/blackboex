defmodule Blackboex.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :plan, :string, null: false, default: "free"
      add :status, :string, null: false, default: "active"
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :cancel_at_period_end, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:subscriptions, [:organization_id])
    create index(:subscriptions, [:stripe_customer_id])
    create index(:subscriptions, [:stripe_subscription_id])
  end
end
