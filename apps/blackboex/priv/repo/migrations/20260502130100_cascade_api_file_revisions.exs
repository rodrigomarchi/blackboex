defmodule Blackboex.Repo.Migrations.CascadeApiFileRevisions do
  use Ecto.Migration

  def change do
    drop constraint(:api_file_revisions, "api_file_revisions_api_file_id_fkey")

    alter table(:api_file_revisions) do
      modify :api_file_id, references(:api_files, type: :binary_id, on_delete: :delete_all),
        null: false
    end
  end
end
