defmodule Blackboex.Projects.ProjectTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Projects.Project

  describe "changeset/2" do
    test "changeset com name valido gera slug com hash" do
      attrs = %{name: "Meu Projeto", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      assert changeset.valid?
      slug = get_change(changeset, :slug)
      assert slug != nil
      # Slug deve ter formato: texto-XXXXXX (6 chars alfanuméricos no final)
      assert Regex.match?(~r/^[a-z0-9][a-z0-9-]*-[a-z0-9]{6}$/, slug)
    end

    test "changeset sem name retorna erro" do
      attrs = %{organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "changeset com name vazio retorna erro" do
      attrs = %{name: "", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "slug e imutavel no update changeset" do
      project = %Project{
        id: Ecto.UUID.generate(),
        name: "Projeto Original",
        slug: "projeto-original-abc123",
        organization_id: Ecto.UUID.generate()
      }

      changeset = Project.update_changeset(project, %{name: "Novo Nome", slug: "slug-novo-xyz"})
      assert changeset.valid?
      # Slug não deve mudar
      refute get_change(changeset, :slug)
    end

    test "slug contem apenas lowercase, numeros, hyphens" do
      attrs = %{name: "Meu Projeto 123!@# Especial", organization_id: Ecto.UUID.generate()}
      changeset = Project.changeset(%Project{}, attrs)
      slug = get_change(changeset, :slug)
      assert Regex.match?(~r/^[a-z0-9-]+$/, slug)
    end
  end

  describe "unique constraints" do
    test "slug e unico por org" do
      org = org_fixture()
      attrs = %{name: "Projeto A", organization_id: org.id}

      {:ok, project1} = %Project{} |> Project.changeset(attrs) |> Blackboex.Repo.insert()

      # Tentar inserir com mesmo slug deve falhar
      {:error, changeset} =
        %Project{}
        |> Project.changeset(%{name: attrs.name, slug: project1.slug, organization_id: org.id})
        |> Blackboex.Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "mesmo slug em orgs diferentes funciona" do
      org1 = org_fixture()
      org2 = org_fixture()

      slug = "projeto-duplicado-abc123"

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
    test "deletar org deleta projetos" do
      user = user_fixture()

      {:ok, %{organization: org}} =
        Blackboex.Organizations.create_organization(user, %{
          name: "Org Temp #{System.unique_integer()}"
        })

      {:ok, _project} =
        %Project{}
        |> Project.changeset(%{name: "Projeto Temp", organization_id: org.id})
        |> Blackboex.Repo.insert()

      assert Blackboex.Repo.all(Project) |> Enum.any?(&(&1.organization_id == org.id))

      Blackboex.Repo.delete!(org)

      refute Blackboex.Repo.all(Project) |> Enum.any?(&(&1.organization_id == org.id))
    end
  end
end
