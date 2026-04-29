defmodule Blackboex.Encrypted.Binary do
  @moduledoc """
  Cloak.Ecto field type for encrypted binary/string values.

  Use as the field type for any schema field that stores a secret at rest:

      schema "project_env_vars" do
        field :encrypted_value, Blackboex.Encrypted.Binary
        ...
      end

  On save, Cloak encrypts the plaintext with the current vault cipher.
  On load, Cloak decrypts — callers see the plaintext when they read the
  field. The column on disk stays `:binary`.
  """

  use Cloak.Ecto.Binary, vault: Blackboex.Vault
end
