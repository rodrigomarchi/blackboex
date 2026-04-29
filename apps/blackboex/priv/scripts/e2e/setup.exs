defmodule E2E.Setup do
  import E2E.Helpers

  def check_server do
    IO.puts(cyan("▸ Checking server at http://localhost:4000..."))

    case Req.get("http://localhost:4000/health", receive_timeout: 3_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        IO.puts(green("  Server is up (HTTP #{status})"))
        :ok

      {:ok, %{status: _status}} ->
        IO.puts(yellow("  Server is responding — proceeding"))
        :ok

      {:error, %{reason: reason}} ->
        {:error,
         "Cannot reach http://localhost:4000 — #{inspect(reason)}. Is `make server` running?"}
    end
  end

  def setup_account do
    IO.puts(cyan("▸ Looking up demo@example.com..."))

    case Blackboex.Accounts.get_user_by_email("demo@example.com") do
      nil ->
        {:error, "User demo@example.com not found. Sign up or run seeds first."}

      user ->
        case Blackboex.Organizations.list_user_organizations(user) do
          [] ->
            {:error, "User has no organizations."}

          [org | _] ->
            IO.puts(green("  Found user #{user.email} in org \"#{org.name}\""))
            {:ok, user, org}
        end
    end
  end

  def cleanup_previous_e2e(org) do
    IO.puts(cyan("▸ Cleaning up all flows..."))

    flows = Blackboex.Flows.list_flows(org.id)

    case flows do
      [] ->
        IO.puts("  No flows found")

      flows ->
        for f <- flows do
          {:ok, _} = Blackboex.Flows.delete_flow(f)
        end

        IO.puts("  Deleted #{length(flows)} flows")
    end

    :ok
  end
end
