defmodule Blackboex.Repo.Migrations.AddHaltSupportToFlowExecutions do
  use Ecto.Migration

  def change do
    alter table(:flow_executions) do
      add :halted_state, :binary
      add :wait_event_type, :string
    end

    create index(:flow_executions, [:wait_event_type], where: "status = 'halted'")
  end
end
