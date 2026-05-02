defmodule Mix.Tasks.Blackboex.Samples.Sync do
  @moduledoc """
  Synchronizes managed sample workspaces.
  """

  use Mix.Task

  alias Blackboex.Projects

  @shortdoc "Synchronizes Blackboex sample workspaces"

  @switches [dry_run: :boolean, org_id: :string, project_id: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)
    sync_opts = Keyword.take(opts, [:org_id, :project_id])

    if Keyword.get(opts, :dry_run, false) do
      counts = Projects.dry_run_sample_workspace_sync(sync_opts)

      Mix.shell().info(
        "Sample workspace dry-run: projects=#{counts.projects} apis=#{counts.apis} flows=#{counts.flows} pages=#{counts.pages} playgrounds=#{counts.playgrounds}"
      )
    else
      case Projects.sync_all_sample_workspaces(sync_opts) do
        {:ok, results} ->
          Mix.shell().info("Synchronized #{length(results)} sample workspace(s).")

        {:error, reason} ->
          Mix.raise("Sample workspace sync failed: #{inspect(reason)}")
      end
    end
  end
end
