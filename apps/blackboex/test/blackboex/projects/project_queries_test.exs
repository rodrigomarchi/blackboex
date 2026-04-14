defmodule Blackboex.Projects.ProjectQueriesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects.ProjectQueries
  alias Blackboex.Repo

  describe "for_organization/1" do
    test "filtra projetos por org_id" do
      user = user_fixture()
      org1 = org_fixture(%{user: user})
      org2 = org_fixture(%{user: user})

      {:ok, %{project: p1}} = Blackboex.Projects.create_project(org1, user, %{name: "Proj Org1"})
      {:ok, %{project: _p2}} = Blackboex.Projects.create_project(org2, user, %{name: "Proj Org2"})

      results = Repo.all(ProjectQueries.for_organization(org1.id))
      assert Enum.any?(results, &(&1.id == p1.id))
      refute Enum.any?(results, &(&1.organization_id != org1.id))
    end
  end

  describe "by_org_and_slug/2" do
    test "retorna projeto correto" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, %{project: project}} =
        Blackboex.Projects.create_project(org, user, %{name: "Slug Test"})

      result = Repo.one(ProjectQueries.by_org_and_slug(org.id, project.slug))
      assert result.id == project.id
    end

    test "com slug inexistente retorna nil" do
      org = org_fixture()
      result = Repo.one(ProjectQueries.by_org_and_slug(org.id, "inexistente-abc123"))
      assert result == nil
    end
  end

  describe "for_user/2" do
    test "retorna projetos onde user e membro" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member = user_fixture()
      Blackboex.Organizations.add_member(org, member, :member)

      {:ok, %{project: project}} = Blackboex.Projects.create_project(org, owner, %{name: "Proj"})
      Blackboex.Projects.add_project_member(project, member, :viewer)

      results = Repo.all(ProjectQueries.for_user(org.id, member.id))
      assert Enum.any?(results, &(&1.id == project.id))
    end

    test "retorna todos projetos se user e org owner" do
      user = user_fixture()
      org = org_fixture(%{user: user})
      {:ok, %{project: project}} = Blackboex.Projects.create_project(org, user, %{name: "Proj"})

      results = Repo.all(ProjectQueries.for_user(org.id, user.id))
      assert Enum.any?(results, &(&1.id == project.id))
    end

    test "retorna todos projetos se user e org admin" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      admin = user_fixture()
      Blackboex.Organizations.add_member(org, admin, :admin)
      {:ok, %{project: project}} = Blackboex.Projects.create_project(org, owner, %{name: "Proj"})

      results = Repo.all(ProjectQueries.for_user(org.id, admin.id))
      assert Enum.any?(results, &(&1.id == project.id))
    end

    test "nao retorna projetos para org member sem project membership" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      member = user_fixture()
      Blackboex.Organizations.add_member(org, member, :member)

      {:ok, %{project: project}} = Blackboex.Projects.create_project(org, owner, %{name: "Proj"})

      results = Repo.all(ProjectQueries.for_user(org.id, member.id))
      refute Enum.any?(results, &(&1.id == project.id))
    end

    test "with_member_count retorna contagem correta" do
      owner = user_fixture()
      org = org_fixture(%{user: owner})
      {:ok, %{project: project}} = Blackboex.Projects.create_project(org, owner, %{name: "Proj"})

      extra = user_fixture()
      Blackboex.Organizations.add_member(org, extra, :member)
      Blackboex.Projects.add_project_member(project, extra, :viewer)

      results =
        ProjectQueries.for_organization(org.id)
        |> ProjectQueries.with_member_count()
        |> Repo.all()

      result = Enum.find(results, &(&1.id == project.id))
      assert result.member_count == 2
    end
  end
end
