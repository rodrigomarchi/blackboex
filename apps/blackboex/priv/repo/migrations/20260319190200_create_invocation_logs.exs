defmodule Blackboex.Repo.Migrations.CreateInvocationLogs do
  use Ecto.Migration

  def change do
    create table(:invocation_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :api_key_id, references(:api_keys, type: :binary_id, on_delete: :nilify_all)
      add :method, :string, null: false
      add :path, :string
      add :status_code, :integer
      add :duration_ms, :integer
      add :request_body_size, :integer
      add :response_body_size, :integer
      add :ip_address, :string

      timestamps(updated_at: false)
    end

    create index(:invocation_logs, [:api_id, :inserted_at])
  end
end
