defmodule Blackboex.Repo do
  use Ecto.Repo,
    otp_app: :blackboex,
    adapter: Ecto.Adapters.Postgres

  use ExAudit.Repo
end
