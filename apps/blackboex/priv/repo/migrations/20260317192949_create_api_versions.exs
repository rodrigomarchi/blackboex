defmodule Blackboex.Repo.Migrations.CreateApiVersions do
  use Ecto.Migration

  def change do
    create table(:api_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :code, :text, null: false
      add :source, :string, null: false
      add :prompt, :text
      add :llm_response, :text
      add :compilation_status, :string, default: "pending"
      add :compilation_errors, {:array, :string}, default: []
      add :diff_summary, :string
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:api_versions, [:api_id, :version_number])
    create index(:api_versions, [:api_id])
  end
end
