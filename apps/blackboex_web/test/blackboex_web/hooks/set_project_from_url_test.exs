defmodule BlackboexWeb.Hooks.SetProjectFromUrlTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Projects
  alias BlackboexWeb.Hooks.SetProjectFromUrl

  @moduletag :unit

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
  end

  describe "on_mount :default" do
    test "sets current_scope with project for org owner" do
      user = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(user, %{name: "My Org"})

      project = Projects.get_default_project(org.id)
      membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} =
        SetProjectFromUrl.on_mount(
          :default,
          %{"org_slug" => org.slug, "project_slug" => project.slug},
          %{},
          socket
        )

      assert socket.assigns.current_scope.project.id == project.id
      assert socket.assigns.current_scope.project_membership == nil
    end

    test "redirects when project_slug is invalid" do
      user = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(user, %{name: "My Org"})

      membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      socket = build_socket(%{current_scope: scope})

      {:halt, socket} =
        SetProjectFromUrl.on_mount(
          :default,
          %{"org_slug" => org.slug, "project_slug" => "nonexistent"},
          %{},
          socket
        )

      assert socket.redirected != nil
    end

    test "redirects when org member has no project access" do
      owner = user_fixture()
      member = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(owner, %{name: "My Org"})

      {:ok, _} = Organizations.add_member(org, member, :member)
      project = Projects.get_default_project(org.id)
      member_membership = Organizations.get_user_membership(org, member)
      scope = Scope.for_user(member) |> Scope.with_organization(org, member_membership)
      socket = build_socket(%{current_scope: scope})

      {:halt, socket} =
        SetProjectFromUrl.on_mount(
          :default,
          %{"org_slug" => org.slug, "project_slug" => project.slug},
          %{},
          socket
        )

      assert socket.redirected != nil
    end

    test "continues when no org in scope" do
      user = user_fixture()
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, ^socket} =
        SetProjectFromUrl.on_mount(
          :default,
          %{"org_slug" => "any", "project_slug" => "any"},
          %{},
          socket
        )
    end
  end
end
