defmodule Blackboex.Repo.Migrations.MultiFileSystem do
  @moduledoc """
  Introduces the multi-file system for API projects.

  - Creates api_files table (virtual filesystem per API)
  - Creates api_file_revisions table (append-only revision history per file)
  - Removes source_code/test_code from apis table
  - Restructures api_versions to use file_snapshots jsonb instead of code/test_code
  """

  use Ecto.Migration

  def change do
    # --- New tables ---

    create table(:api_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_id, references(:apis, type: :binary_id, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :content, :text
      add :file_type, :string, null: false

      timestamps()
    end

    create unique_index(:api_files, [:api_id, :path])
    create index(:api_files, [:api_id])

    create table(:api_file_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :api_file_id, references(:api_files, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content, :text, null: false
      add :diff, :text
      add :message, :string
      add :source, :string, null: false
      add :revision_number, :integer, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create unique_index(:api_file_revisions, [:api_file_id, :revision_number])
    create index(:api_file_revisions, [:api_file_id])

    # --- Modify apis table ---

    alter table(:apis) do
      remove :source_code, :text
      remove :test_code, :text
    end

    # --- Modify api_versions table ---

    alter table(:api_versions) do
      remove :code, :text
      remove :test_code, :text
      remove :llm_response, :text
      add :file_snapshots, :jsonb, null: false, default: "[]"
      add :version_label, :string
    end
  end
end
