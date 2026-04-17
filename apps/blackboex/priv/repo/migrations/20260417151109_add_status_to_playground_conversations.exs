defmodule Blackboex.Repo.Migrations.AddStatusToPlaygroundConversations do
  use Ecto.Migration

  def change do
    alter table(:playground_conversations) do
      add :status, :string, null: false, default: "active"
      add :archived_at, :utc_datetime_usec
    end

    # Drop the strict 1:1 index and replace it with a partial unique so each
    # playground can only have ONE active conversation at a time, while
    # archived threads can pile up freely.
    drop_if_exists unique_index(:playground_conversations, [:playground_id])

    create unique_index(:playground_conversations, [:playground_id],
             where: "status = 'active'",
             name: :playground_conversations_unique_active
           )

    create index(:playground_conversations, [:playground_id, :inserted_at])
  end
end
