defmodule Blackboex.ProjectsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects
  alias Blackboex.Projects.{Project, ProjectMembership}

  describe "create_project/3" do
    test "cria projeto e membership admin para o criador" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      assert {:ok, %{project: project, membership: membership}} =
               Projects.create_project(org, user, %{name: "Meu Projeto"})

      assert project.organization_id == org.id
      assert project.name == "Meu Projeto"
      assert membership.user_id == user.id
      assert membership.role == :admin
    end

    test "cria projeto com slug gerado automaticamente" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Auto Slug"})

      assert project.slug != nil
      assert String.length(project.slug) > 0
    end
  end

  describe "create_default_project/2" do
    test "cria projeto com name Default" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_default_project(org, user)

      assert project.name == "Default"
      assert project.organization_id == org.id
    end
  end

  describe "list_projects/1" do
    test "retorna todos os projetos da org" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: p1}} = Projects.create_project(org, user, %{name: "Projeto 1"})
      {:ok, %{project: p2}} = Projects.create_project(org, user, %{name: "Projeto 2"})

      projects = Projects.list_projects(org.id)
      project_ids = Enum.map(projects, & &1.id)

      assert p1.id in project_ids
      assert p2.id in project_ids
    end
  end

  describe "list_user_projects/2" do
    test "retorna apenas projetos acessiveis para org member sem project membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      other_user = user_fixture()
      Blackboex.Organizations.add_member(org, other_user, :member)

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto Privado"})

      # other_user não tem project membership, não deve ver
      projects = Projects.list_user_projects(org.id, other_user.id)
      refute Enum.any?(projects, &(&1.id == project.id))
    end

    test "retorna todos os projetos para org owner" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})

      projects = Projects.list_user_projects(org.id, user.id)
      assert Enum.any?(projects, &(&1.id == project.id))
    end

    test "retorna todos os projetos para org admin" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      admin = user_fixture()
      Blackboex.Organizations.add_member(org, admin, :admin)

      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Projeto"})

      projects = Projects.list_user_projects(org.id, admin.id)
      assert Enum.any?(projects, &(&1.id == project.id))
    end
  end

  describe "get_project_by_slug/2" do
    test "retorna projeto correto" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Slug Test"})

      found = Projects.get_project_by_slug(org.id, project.slug)
      assert found.id == project.id
    end

    test "retorna nil com slug errado" do
      org = org_fixture()
      assert nil == Projects.get_project_by_slug(org.id, "nao-existe-abc123")
    end
  end

  describe "update_project/2" do
    test "atualiza nome mas NAO o slug" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Original"})
      original_slug = project.slug

      {:ok, updated} = Projects.update_project(project, %{name: "Novo Nome", slug: "slug-novo"})

      assert updated.name == "Novo Nome"
      assert updated.slug == original_slug
    end
  end

  describe "delete_project/1" do
    test "deleta projeto com cascade" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Para Deletar"})

      assert {:ok, _} = Projects.delete_project(project)
      assert nil == Blackboex.Repo.get(Project, project.id)
    end
  end

  describe "member management" do
    test "add_project_member adiciona membro com role" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})
      new_member = user_fixture()

      assert {:ok, membership} = Projects.add_project_member(project, new_member, :editor)
      assert membership.user_id == new_member.id
      assert membership.role == :editor
    end

    test "add_project_member duplicado retorna erro" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})

      # user já é admin via create_project
      assert {:error, _} = Projects.add_project_member(project, user, :viewer)
    end

    test "remove_project_member remove membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: _project, membership: membership}} =
        Projects.create_project(org, user, %{name: "Projeto"})

      assert {:ok, _} = Projects.remove_project_member(membership)
      assert nil == Blackboex.Repo.get(ProjectMembership, membership.id)
    end

    test "update_project_member_role muda role" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: _project, membership: membership}} =
        Projects.create_project(org, user, %{name: "Projeto"})

      assert {:ok, updated} = Projects.update_project_member_role(membership, :viewer)
      assert updated.role == :viewer
    end

    test "list_project_members retorna membros com user preloaded" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})

      members = Projects.list_project_members(project.id)
      assert members != []
      assert hd(members).user != nil
    end
  end

  describe "user_has_project_access?/3" do
    test "retorna true para membro direto do projeto" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})
      member = user_fixture()
      Projects.add_project_member(project, member, :viewer)
      membership = Blackboex.Organizations.get_user_membership(org, member)

      assert Projects.user_has_project_access?(org, membership, project, member)
    end

    test "retorna true para org owner sem project membership" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Projeto"})
      membership = Blackboex.Organizations.get_user_membership(org, user)

      assert Projects.user_has_project_access?(org, membership, project, user)
    end

    test "retorna true para org admin sem project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      admin = user_fixture()
      Blackboex.Organizations.add_member(org, admin, :admin)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Projeto"})
      membership = Blackboex.Organizations.get_user_membership(org, admin)

      assert Projects.user_has_project_access?(org, membership, project, admin)
    end

    test "retorna false para org member sem project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member = user_fixture()
      Blackboex.Organizations.add_member(org, member, :member)
      {:ok, %{project: project}} = Projects.create_project(org, owner, %{name: "Projeto"})
      membership = Blackboex.Organizations.get_user_membership(org, member)

      refute Projects.user_has_project_access?(org, membership, project, member)
    end
  end

  describe "list_projects_with_counts/1" do
    test "returns counts for each resource type per project" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      # org_fixture creates a "Default" project automatically; use it as p2 (empty)
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

      assert p2_row.pages_count == 0
      assert p2_row.apis_count == 0
      assert p2_row.flows_count == 0
      assert p2_row.playgrounds_count == 0
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
    test "retorna membros da org sem project membership" do
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

    test "retorna lista vazia quando todos membros da org ja estao no projeto" do
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
