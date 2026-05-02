defmodule Blackboex.Repo.Migrations.CreateOrgInvitations do
  use Ecto.Migration

  def change do
    create table(:org_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :email, :string, null: false
      add :role, :string, null: false
      add :token_hash, :binary, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:org_invitations, [:token_hash])

    create unique_index(:org_invitations, [:organization_id, :email],
             where: "accepted_at IS NULL",
             name: :org_invitations_pending_email_unique
           )

    create index(:org_invitations, [:organization_id])
    create index(:org_invitations, [:expires_at])
  end
end
