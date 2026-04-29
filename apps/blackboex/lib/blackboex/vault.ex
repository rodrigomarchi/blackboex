defmodule Blackboex.Vault do
  @moduledoc """
  Cloak vault for at-rest encryption of sensitive fields (project env var
  values, LLM API keys).

  Uses AES-256-GCM with a per-deployment master key loaded at boot from
  the `CLOAK_KEY` environment variable (base64-encoded 32 bytes). Dev and
  test environments use a static key defined in their respective config
  files so local workflows never depend on an env var being set.

  The Vault GenServer must be started before the Repo (so the first
  schema load can decrypt), which is wired in `Blackboex.Application`.
  """

  use Cloak.Vault, otp_app: :blackboex
end
