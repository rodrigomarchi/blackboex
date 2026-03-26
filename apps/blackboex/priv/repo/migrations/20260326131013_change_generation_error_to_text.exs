defmodule Blackboex.Repo.Migrations.ChangeGenerationErrorToText do
  use Ecto.Migration

  def change do
    alter table(:apis) do
      modify :generation_error, :text, from: :string
    end
  end
end
