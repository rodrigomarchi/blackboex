alias Blackboex.{Accounts, Organizations, Projects}

if System.get_env("BLACKBOEX_DEMO") == "true" do
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
end

:ok
