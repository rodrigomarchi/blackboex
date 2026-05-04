defmodule ProjectMembershipTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Repo

  describe "changeset/2" do
    test "valid changeset with role :admin" do
      attrs = %{project_id: Ecto.UUID.generate(), user_id: 1, role: :admin}
      changeset = ProjectMembership.changeset(%ProjectMembership{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with role :editor" do
      attrs = %{project_id: Ecto.UUID.generate(), user_id: 1, role: :editor}
      changeset = ProjectMembership.changeset(%ProjectMembership{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with role :viewer" do
      attrs = %{project_id: Ecto.UUID.generate(), user_id: 1, role: :viewer}
      changeset = ProjectMembership.changeset(%ProjectMembership{}, attrs)
      assert changeset.valid?
    end

    test "changeset with invalid role returns error" do
      attrs = %{project_id: Ecto.UUID.generate(), user_id: 1, role: :superadmin}
      changeset = ProjectMembership.changeset(%ProjectMembership{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset).role != []
    end
  end

  describe "unique constraints" do
    test "user can have only one membership per project" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, project} =
        %Project{}
        |> Project.changeset(%{name: "Test Project", organization_id: org.id})
        |> Repo.insert()

      {:ok, _} =
        %ProjectMembership{}
        |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: :admin})
        |> Repo.insert()

      {:error, changeset} =
        %ProjectMembership{}
        |> ProjectMembership.changeset(%{
          project_id: project.id,
          user_id: user.id,
          role: :viewer
        })
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).user_id
    end
  end

  describe "cascade delete" do
    test "deleting project deletes memberships" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, project} =
        %Project{}
        |> Project.changeset(%{name: "Temp Project", organization_id: org.id})
        |> Repo.insert()

      {:ok, _} =
        %ProjectMembership{}
        |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: :admin})
        |> Repo.insert()

      Repo.delete!(project)

      refute Repo.all(ProjectMembership) |> Enum.any?(&(&1.project_id == project.id))
    end

    test "deleting user deletes memberships" do
      user = user_fixture()
      org = org_fixture(%{user: user})

      {:ok, project} =
        %Project{}
        |> Project.changeset(%{name: "Temp Project", organization_id: org.id})
        |> Repo.insert()

      {:ok, _} =
        %ProjectMembership{}
        |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: :admin})
        |> Repo.insert()

      Repo.delete!(user)

      refute Repo.all(ProjectMembership) |> Enum.any?(&(&1.user_id == user.id))
    end
  end
end
