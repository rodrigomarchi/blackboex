defmodule Blackboex.Projects.SamplesTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Apis
  alias Blackboex.Flows
  alias Blackboex.Pages
  alias Blackboex.Playgrounds
  alias Blackboex.Projects
  alias Blackboex.Repo
  alias Blackboex.Samples.Manifest

  describe "provision_for_org/2" do
    test "creates the managed Exemplos project and all manifest samples" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      # org_fixture already provisions the sample workspace through Organizations.
      project = Projects.get_default_project(org.id)

      assert project.name == "Exemplos"
      assert project.sample_workspace == true
      assert project.sample_manifest_version == Manifest.version()
      assert project.sample_synced_at

      assert length(Apis.list_apis_for_project(project.id)) == length(Manifest.list_by_kind(:api))

      assert length(Flows.list_flows_for_project(project.id)) ==
               length(Manifest.list_by_kind(:flow))

      assert length(Pages.list_pages(project.id)) == length(Manifest.list_by_kind(:page))

      assert length(Playgrounds.list_playgrounds(project.id)) ==
               length(Manifest.list_by_kind(:playground))
    end

    test "creates compiled APIs and active flows with sample UUIDs" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      project = Projects.get_default_project(org.id)

      assert Enum.all?(Apis.list_apis_for_project(project.id), fn api ->
               api.status == "compiled" and is_binary(api.sample_uuid)
             end)

      flows = Flows.list_flows_for_project(project.id)
      assert Enum.all?(flows, &is_binary(&1.sample_uuid))
      assert Enum.any?(flows, &(&1.name == "Echo Transform" and &1.status == "active"))
    end

    test "preserves page hierarchy and renders flow tokens in playgrounds" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      project = Projects.get_default_project(org.id)

      pages = Pages.list_pages(project.id)
      child = Enum.find(pages, &(&1.title == "[Demo] Padrões de Código Elixir"))
      parent = Enum.find(pages, &(&1.title == "[Demo] Guia de Formatação"))

      assert child.parent_id == parent.id

      playground =
        Enum.find(Playgrounds.list_playgrounds(project.id), &(&1.name =~ "Chamando Fluxo"))

      refute playground.code =~ "{{flow:"
      refute playground.code =~ "FLOW_TOKEN_NOT_FOUND"
    end
  end

  describe "sync_sample_workspace/1" do
    test "is idempotent and does not duplicate samples" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      project = Projects.get_default_project(org.id)

      assert {:ok, _} = Projects.sync_sample_workspace(project)
      assert {:ok, _} = Projects.sync_sample_workspace(Repo.reload!(project))

      assert length(Apis.list_apis_for_project(project.id)) == length(Manifest.list_by_kind(:api))

      assert length(Flows.list_flows_for_project(project.id)) ==
               length(Manifest.list_by_kind(:flow))

      assert length(Pages.list_pages(project.id)) == length(Manifest.list_by_kind(:page))

      assert length(Playgrounds.list_playgrounds(project.id)) ==
               length(Manifest.list_by_kind(:playground))
    end

    test "overwrites managed samples but leaves non-sample resources untouched" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      project = Projects.get_default_project(org.id)

      sample_page =
        project.id
        |> Pages.list_pages()
        |> Enum.find(& &1.sample_uuid)

      {:ok, _} = Pages.update_page(sample_page, %{content: "changed by user"})
      untouched = page_fixture(%{user: user, org: org, project: project, title: "User note"})

      assert {:ok, _} = Projects.sync_sample_workspace(project)

      assert Repo.reload!(sample_page).content != "changed by user"
      assert Repo.reload!(untouched).title == "User note"
    end

    test "returns an error for regular projects" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Regular"})

      assert {:error, {:not_sample_workspace, project_id}} =
               Projects.sync_sample_workspace(project)

      assert project_id == project.id
    end
  end

  describe "sync_all_sample_workspaces/1" do
    test "syncs sample projects and ignores regular projects" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      sample_project = Projects.get_default_project(org.id)
      {:ok, %{project: regular_project}} = Projects.create_project(org, user, %{name: "Regular"})

      assert {:ok, [result]} = Projects.sync_all_sample_workspaces(project_id: sample_project.id)
      assert result.project.id == sample_project.id

      assert Projects.dry_run_sample_workspace_sync(project_id: regular_project.id).projects == 0
    end

    test "does not recreate a deleted sample project" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      project = Projects.get_default_project(org.id)

      assert {:ok, _} = Projects.delete_project(project)
      assert {:ok, []} = Projects.sync_all_sample_workspaces(org_id: org.id)
      assert [] = Projects.list_projects(org.id)
    end
  end
end
