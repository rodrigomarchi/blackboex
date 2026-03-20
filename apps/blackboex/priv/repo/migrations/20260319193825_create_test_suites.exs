defmodule Blackboex.Repo.Migrations.CreateTestSuites do
  use Ecto.Migration

  def change do
    create table(:test_suites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :version_number, :integer
      add :test_code, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :results, :map
      add :total_tests, :integer, default: 0
      add :passed_tests, :integer, default: 0
      add :failed_tests, :integer, default: 0
      add :duration_ms, :integer, default: 0

      timestamps()
    end

    create index(:test_suites, [:api_id])
    create index(:test_suites, [:inserted_at])
  end
end
