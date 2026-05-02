defmodule Mix.Tasks.Blackboex.Samples.SyncTest do
  use Blackboex.DataCase, async: false

  import ExUnit.CaptureIO

  alias Blackboex.Projects

  @task "blackboex.samples.sync"

  setup do
    Mix.Task.reenable(@task)
    :ok
  end

  test "--dry-run reports counts without mutating" do
    user = user_fixture()
    org = org_fixture(%{user: user})
    project = Projects.get_default_project(org.id)
    before_synced_at = project.sample_synced_at

    output =
      capture_io(fn ->
        Mix.Task.run(@task, ["--dry-run", "--project-id", project.id])
      end)

    assert output =~ "Sample workspace dry-run: projects=1"
    assert Projects.get_project(org.id, project.id).sample_synced_at == before_synced_at
  end

  test "--project-id synchronizes only the selected sample project" do
    user = user_fixture()
    org = org_fixture(%{user: user})
    project = Projects.get_default_project(org.id)

    output =
      capture_io(fn ->
        Mix.Task.run(@task, ["--project-id", project.id])
      end)

    assert output =~ "Synchronized 1 sample workspace(s)."
  end

  test "--org-id ignores regular projects" do
    user = user_fixture()
    org = org_fixture(%{user: user})
    {:ok, %{project: _regular}} = Projects.create_project(org, user, %{name: "Regular"})

    output =
      capture_io(fn ->
        Mix.Task.run(@task, ["--org-id", org.id])
      end)

    assert output =~ "Synchronized 1 sample workspace(s)."
  end
end
