defmodule Blackboex.ProjectsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects
  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Blackboex.Samples.Manifest

  describe "create_project/3" do
    test "creates project and admin membership for the creator" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      assert {:ok, %{project: project, membership: membership}} =
               Projects.create_project(org, user, %{name: "My Project"})

      assert project.organization_id == org.id
      assert project.name == "My Project"
      assert membership.user_id == user.id
      assert membership.role == :admin
    end

    test "creates project with automatically generated slug" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Auto Slug"})

      assert project.slug != nil
      assert String.length(project.slug) > 0
    end
  end

  describe "create_default_project/2" do
    test "creates project with Default name" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_default_project(org, user)

      assert project.name == "Default"
      assert project.organization_id == org.id
    end
  end

  describe "list_projects/1" do
    test "returns all organization projects" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: p1}} = Projects.create_project(org, user, %{name: "Project 1"})
      {:ok, %{project: p2}} = Projects.create_project(org, user, %{name: "Project 2"})

      projects = Projects.list_projects(org.id)
      project_ids = Enum.map(projects, & &1.id)

      assert p1.id in project_ids
      assert p2.id in project_ids
    end
  end

  describe "list_user_projects/2" do
    test "returns only accessible projects for org member without project membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      other_user = user_fixture()
      Blackboex.Organizations.add_member(org, other_user, :member)

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Private Project"})

      # other_user has no project membership and must not see it.
      projects = Projects.list_user_projects(org.id, other_user.id)
      refute Enum.any?(projects, &(&1.id == project.id))
    end

    test "returns all projects for org owner" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})

      projects = Projects.list_user_projects(org.id, user.id)
      assert Enum.any?(projects, &(&1.id == project.id))
    end

    test "returns all projects for org admin" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      admin = user_fixture()
      Blackboex.Organizations.add_member(org, admin, :admin)

      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Project"})

      projects = Projects.list_user_projects(org.id, admin.id)
      assert Enum.any?(projects, &(&1.id == project.id))
    end
  end

  describe "get_project_by_slug/2" do
    test "returns the correct project" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Slug Test"})

      found = Projects.get_project_by_slug(org.id, project.slug)
      assert found.id == project.id
    end

    test "returns nil with a wrong slug" do
      org = org_fixture()
      assert nil == Projects.get_project_by_slug(org.id, "does-not-exist-abc123")
    end
  end

  describe "update_project/2" do
    test "updates name but not slug" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Original"})
      original_slug = project.slug

      {:ok, updated} = Projects.update_project(project, %{name: "New Name", slug: "new-slug"})

      assert updated.name == "New Name"
      assert updated.slug == original_slug
    end
  end

  describe "delete_project/1" do
    test "deletes project with cascade" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "To Delete"})

      assert {:ok, _} = Projects.delete_project(project)
      assert nil == Blackboex.Repo.get(Project, project.id)
    end
  end

  describe "member management" do
    test "add_project_member adds member with role" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})
      new_member = user_fixture()

      assert {:ok, membership} = Projects.add_project_member(project, new_member, :editor)
      assert membership.user_id == new_member.id
      assert membership.role == :editor
    end

    test "duplicate add_project_member returns error" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})

      # user is already admin through create_project.
      assert {:error, _} = Projects.add_project_member(project, user, :viewer)
    end

    test "remove_project_member remove membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: _project, membership: membership}} =
        Projects.create_project(org, user, %{name: "Project"})

      assert {:ok, _} = Projects.remove_project_member(membership)
      assert nil == Blackboex.Repo.get(ProjectMembership, membership.id)
    end

    test "update_project_member_role changes role" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: _project, membership: membership}} =
        Projects.create_project(org, user, %{name: "Project"})

      assert {:ok, updated} = Projects.update_project_member_role(membership, :viewer)
      assert updated.role == :viewer
    end

    test "list_project_members returns members with preloaded user" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})

      members = Projects.list_project_members(project.id)
      assert members != []
      assert hd(members).user != nil
    end
  end

  describe "user_has_project_access?/3" do
    test "returns true for direct project member" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})
      member = user_fixture()
      Projects.add_project_member(project, member, :viewer)
      membership = Blackboex.Organizations.get_user_membership(org, member)

      assert Projects.user_has_project_access?(org, membership, project, member)
    end

    test "returns true for org owner without project membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Project"})
      membership = Blackboex.Organizations.get_user_membership(org, user)

      assert Projects.user_has_project_access?(org, membership, project, user)
    end

    test "returns true for org admin without project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      admin = user_fixture()
      Blackboex.Organizations.add_member(org, admin, :admin)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Project"})
      membership = Blackboex.Organizations.get_user_membership(org, admin)

      assert Projects.user_has_project_access?(org, membership, project, admin)
    end

    test "returns false for org member without project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member = user_fixture()
      Blackboex.Organizations.add_member(org, member, :member)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Project"})
      membership = Blackboex.Organizations.get_user_membership(org, member)

      refute Projects.user_has_project_access?(org, membership, project, member)
    end
  end

  describe "list_projects_with_counts/1" do
    test "returns counts for each resource type per project" do
      user = user_fixture()
      org = org_fixture(%{user: user, materialize_samples: true})

      # org_fixture creates the managed "Examples" project automatically.
      p2 = Projects.get_default_project(org.id)
      {:ok, %{project: p1}} = Projects.create_project(org, user, %{name: "Alpha Project"})

      # p1: 3 pages, 2 apis, 1 flow, 0 playgrounds
      _page1 = page_fixture(%{user: user, org: org, project: p1})
      _page2 = page_fixture(%{user: user, org: org, project: p1})
      _page3 = page_fixture(%{user: user, org: org, project: p1})
      _api1 = api_fixture(%{user: user, org: org, project: p1})
      _api2 = api_fixture(%{user: user, org: org, project: p1})
      _flow1 = flow_fixture(%{user: user, org: org, project: p1})

      results = Projects.list_projects_with_counts(org)

      assert length(results) == 2

      p1_row = Enum.find(results, &(&1.project.id == p1.id))
      p2_row = Enum.find(results, &(&1.project.id == p2.id))

      assert p1_row.pages_count == 3
      assert p1_row.apis_count == 2
      assert p1_row.flows_count == 1
      assert p1_row.playgrounds_count == 0

      assert p2_row.pages_count == length(Manifest.list_by_kind(:page))
      assert p2_row.apis_count == length(Manifest.list_by_kind(:api))
      assert p2_row.flows_count == length(Manifest.list_by_kind(:flow))

      assert p2_row.playgrounds_count ==
               length(Manifest.list_by_kind(:playground))
    end

    test "returns results ordered by project name ASC" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      # org starts with a "Default" project; add more to verify ordering
      {:ok, %{project: _p_z}} = Projects.create_project(org, user, %{name: "Zebra"})
      {:ok, %{project: _p_a}} = Projects.create_project(org, user, %{name: "Apple"})
      {:ok, %{project: _p_m}} = Projects.create_project(org, user, %{name: "Mango"})

      results = Projects.list_projects_with_counts(org)
      names = Enum.map(results, & &1.project.name)

      assert names == Enum.sort(names)
    end

    test "returns empty list for org with no projects" do
      org = org_fixture()
      # delete the default project to get a clean state
      default = Projects.get_default_project(org.id)
      if default, do: Projects.delete_project(default)

      assert [] = Projects.list_projects_with_counts(org)
    end
  end

  describe "list_eligible_members/2" do
    test "returns org members without project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member1 = user_fixture()
      member2 = user_fixture()
      Blackboex.Organizations.add_member(org, member1, :member)
      Blackboex.Organizations.add_member(org, member2, :member)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Proj"})
      Projects.add_project_member(project, member1, :viewer)

      eligible = Projects.list_eligible_members(org, project)
      user_ids = Enum.map(eligible, & &1.user_id)

      # member2 is in org but not in project
      assert member2.id in user_ids
      # member1 is already in project
      refute member1.id in user_ids
      # owner was added during project creation
      refute owner.id in user_ids
    end

    test "returns empty list when every org member is already in the project" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member = user_fixture()
      Blackboex.Organizations.add_member(org, member, :member)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Proj"})
      Projects.add_project_member(project, member, :viewer)

      eligible = Projects.list_eligible_members(org, project)
      user_ids = Enum.map(eligible, & &1.user_id)

      refute member.id in user_ids
      refute owner.id in user_ids
    end
  end
end
