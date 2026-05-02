# Demo seed wrapper.
#
# Usage:
#   mix run apps/blackboex/priv/repo/seeds_demo.exs
#
# The sample catalogue lives in Blackboex.Samples.Manifest. This script only
# synchronizes existing managed sample workspaces for demo@example.com.

alias Blackboex.{Accounts, Organizations, Projects}

user =
  Accounts.get_user_by_email("demo@example.com") ||
    raise "User demo@example.com not found. Create the demo user first."

user
|> Organizations.list_user_organizations()
|> Enum.each(fn org ->
  case Projects.sync_all_sample_workspaces(org_id: org.id) do
    {:ok, results} ->
      IO.puts("Synced #{length(results)} sample workspace(s) for #{org.name}.")

    {:error, reason} ->
      raise "Failed to sync sample workspaces for #{org.name}: #{inspect(reason)}"
  end
end)

:ok
