defmodule Blackboex.Repo.Migrations.AddErrorMessageToInvocationLogs do
  use Ecto.Migration

  def change do
    alter table(:invocation_logs) do
      add :error_message, :text
    end
  end
end
