defmodule Blackboex.Repo.Migrations.DropFunWithFlagsTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:fun_with_flags_toggles)
  end

  def down do
    :ok
  end
end
