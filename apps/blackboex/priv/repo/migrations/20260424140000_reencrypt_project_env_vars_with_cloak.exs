defmodule Blackboex.Repo.Migrations.ReencryptProjectEnvVarsWithCloak do
  @moduledoc """
  One-off data migration: rewrite every `project_env_vars.encrypted_value`
  row from the MVP Base64 placeholder to the Cloak.Ecto AES-256-GCM envelope.

  The column type on disk stays `:binary`; only the byte contents change.
  Runs inside a single transaction — the table is small (project-scoped
  secrets). If the column is already empty or the blob cannot be decoded
  as Base64 (already Cloak-wrapped), the row is skipped so the migration
  is idempotent and safe to re-run.
  """

  use Ecto.Migration

  alias Blackboex.Repo
  alias Blackboex.Vault

  def up do
    Enum.each(fetch_rows(), &migrate_row/1)
  end

  def down do
    # Reverse: re-encode each current value back to raw Base64. The plaintext
    # is recoverable via the Vault (still started), so this is purely a
    # format revert. Only run if the Vault key is still available.
    Enum.each(fetch_rows(), &revert_row/1)
  end

  defp fetch_rows do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(Repo, "SELECT id, encrypted_value FROM project_env_vars", [])

    rows
  end

  defp migrate_row([id, blob]) do
    with {:base64, {:ok, plaintext}} <- {:base64, Base.decode64(blob)},
         {:encrypt, {:ok, ciphertext}} <- {:encrypt, Vault.encrypt(plaintext)} do
      write_value(id, ciphertext)
    else
      {:base64, :error} ->
        # Not Base64 — likely already Cloak-encrypted from a prior run. Skip.
        :ok

      {:encrypt, {:error, reason}} ->
        raise "Vault encrypt failed for project_env_var #{inspect(id)}: #{inspect(reason)}"
    end
  end

  defp revert_row([id, blob]) do
    case Vault.decrypt(blob) do
      {:ok, plaintext} ->
        write_value(id, Base.encode64(plaintext))

      {:error, _} ->
        # Already raw Base64 (or unrecoverable) — skip.
        :ok
    end
  end

  defp write_value(id, new_blob) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE project_env_vars SET encrypted_value = $1 WHERE id = $2",
      [new_blob, id]
    )
  end
end
