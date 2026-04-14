defmodule Blackboex.Accounts.ScopeTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  @moduletag :unit

  describe "for_user/1" do
    test "creates scope with user" do
      user = user_fixture()
      scope = Scope.for_user(user)
      assert scope.user.id == user.id
      assert scope.organization == nil
      assert scope.membership == nil
    end

    test "returns nil for nil user" do
      assert Scope.for_user(nil) == nil
    end
  end

  describe "with_organization/3" do
    test "sets organization and membership on scope" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

      assert scope.user.id == user.id
      assert scope.organization.id == org.id
      assert scope.membership.id == membership.id
    end
  end

  describe "with_project/3" do
    test "sets project and project_membership on scope" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      membership = Organizations.get_user_membership(org, user)
      project = Blackboex.Projects.get_default_project(org.id)
      project_membership = Blackboex.Projects.get_project_membership(project, user)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)
        |> Scope.with_project(project, project_membership)

      assert scope.project.id == project.id
      assert scope.project_membership.id == project_membership.id
    end
  end

  describe "project_role/1" do
    setup do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      membership = Organizations.get_user_membership(org, user)
      project = Blackboex.Projects.get_default_project(org.id)
      project_membership = Blackboex.Projects.get_project_membership(project, user)

      base_scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      %{
        base_scope: base_scope,
        org: org,
        project: project,
        project_membership: project_membership
      }
    end

    test "returns role from project_membership", %{
      base_scope: base_scope,
      project: project,
      project_membership: pm
    } do
      scope = Scope.with_project(base_scope, project, pm)
      assert Scope.project_role(scope) == pm.role
    end

    test "returns :implicit_admin for org owner without project_membership", %{
      base_scope: base_scope,
      project: project
    } do
      scope = Scope.with_project(base_scope, project, nil)
      assert Scope.project_role(scope) == :implicit_admin
    end

    test "returns :implicit_admin for org admin without project_membership" do
      owner = user_fixture()
      [org] = Organizations.list_user_organizations(owner)
      admin = user_fixture()
      {:ok, _} = Organizations.add_member(org, admin, :admin)
      admin_membership = Organizations.get_user_membership(org, admin)
      project = Blackboex.Projects.get_default_project(org.id)

      scope =
        Scope.for_user(admin)
        |> Scope.with_organization(org, admin_membership)
        |> Scope.with_project(project, nil)

      assert Scope.project_role(scope) == :implicit_admin
    end

    test "returns nil if no project set" do
      user = user_fixture()
      scope = Scope.for_user(user)
      assert Scope.project_role(scope) == nil
    end
  end
end
