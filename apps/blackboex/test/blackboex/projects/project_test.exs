defmodule Blackboex.Projects.ProjectTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects.Project

  describe "changeset/2" do
    test "changeset with a valid name generates a hashed slug" do
      attrs = %{name: "My Project", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      assert changeset.valid?
      slug = get_change(changeset, :slug)
      assert slug != nil
      # Slug must use the text-XXXXXX format with 6 alphanumeric chars at the end.
      assert Regex.match?(~r/^[a-z0-9][a-z0-9-]*-[a-z0-9]{6}$/, slug)
    end

    test "changeset without a name returns an error" do
      attrs = %{organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "changeset with an empty name returns an error" do
      attrs = %{name: "", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "slug is immutable in the update changeset" do
      project = %Project{
        id: Ecto.UUID.generate(),
        name: "Original Project",
        slug: "original-project-abc123",
        organization_id: Ecto.UUID.generate()
      }

      changeset = Project.update_changeset(project, %{name: "New Name", slug: "new-slug-xyz"})
      assert changeset.valid?
      # Slug must not change.
      refute get_change(changeset, :slug)
    end

    test "slug contains only lowercase characters, numbers and hyphens" do
      attrs = %{name: "My Special Project 123!@#", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      slug = get_change(changeset, :slug)
      assert Regex.match?(~r/^[a-z0-9-]+$/, slug)
    end
  end

  describe "unique constraints" do
    test "slug is unique per organization" do
      org = org_fixture()
      attrs = %{name: "Project A", organization_id: org.id}

      {:ok, project1} = %Project{} |> Project.changeset(attrs) |> Blackboex.Repo.insert()

      # Inserting the same slug in the same organization must fail.
      {:error, changeset} =
        %Project{}
        |> Project.changeset(%{name: attrs.name, slug: project1.slug, organization_id: org.id})
        |> Blackboex.Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "the same slug works across different organizations" do
      org1 = org_fixture()
      org2 = org_fixture()

      slug = "duplicate-project-abc123"

      {:ok, _} =
        %Project{}
        |> Project.changeset(%{name: "Proj", slug: slug, organization_id: org1.id})
        |> Blackboex.Repo.insert()

      {:ok, _} =
        %Project{}
        |> Project.changeset(%{name: "Proj", slug: slug, organization_id: org2.id})
        |> Blackboex.Repo.insert()
    end
  end

  describe "cascade delete" do
    test "deleting an organization deletes projects" do
      user = user_fixture()

      {:ok, %{organization: org}} =
        Blackboex.Organizations.create_organization(user, %{
          name: "Org Temp #{System.unique_integer()}"
        })

      {:ok, _project} =
        %Project{}
        |> Project.changeset(%{name: "Temporary Project", organization_id: org.id})
        |> Blackboex.Repo.insert()

      assert Blackboex.Repo.all(Project) |> Enum.any?(&(&1.organization_id == org.id))

      Blackboex.Repo.delete!(org)

      refute Blackboex.Repo.all(Project) |> Enum.any?(&(&1.organization_id == org.id))
    end
  end
end
