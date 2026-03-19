defmodule Blackboex.Repo.Migrations.CreateTestRequests do
  use Ecto.Migration

  def change do
    create table(:test_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :method, :string, null: false
      add :path, :string, null: false
      add :headers, :map, default: %{}
      add :body, :text
      add :response_status, :integer
      add :response_headers, :map, default: %{}
      add :response_body, :text
      add :duration_ms, :integer

      timestamps(updated_at: false)
    end

    create index(:test_requests, [:api_id])
    create index(:test_requests, [:user_id])
    create index(:test_requests, [:inserted_at])
  end
end
