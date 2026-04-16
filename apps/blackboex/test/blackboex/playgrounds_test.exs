defmodule Blackboex.PlaygroundsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Playground

  setup [:create_user_and_org]

  describe "create_playground/1" do
    setup [:create_project]

    test "creates a playground with valid attrs", %{org: org, project: project, user: user} do
      attrs = %{
        name: "My Elixir REPL",
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, %Playground{} = pg} = Playgrounds.create_playground(attrs)
      assert pg.name == "My Elixir REPL"
      assert pg.code == ""
      assert pg.last_output == nil
      assert pg.project_id == project.id
      assert pg.slug =~ ~r/^my-elixir-repl-[a-z0-9]{6}$/
    end

    test "fails without required fields" do
      assert {:error, changeset} = Playgrounds.create_playground(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates code max length", %{org: org, project: project, user: user} do
      attrs = %{
        name: "Big Code",
        code: String.duplicate("a", 262_145),
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:error, changeset} = Playgrounds.create_playground(attrs)
      assert %{code: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most"
    end

    test "enforces unique slug per project", %{org: org, project: project, user: user} do
      pg = playground_fixture(%{user: user, org: org, project: project, name: "My Playground"})

      attrs = %{
        name: "Another Playground",
        slug: pg.slug,
        organization_id: org.id,
        project_id: project.id,
        user_id: pg.user_id
      }

      assert {:error, changeset} = Playgrounds.create_playground(attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_playgrounds/1" do
    setup [:create_project]

    test "returns playgrounds for a project", %{user: user, org: org, project: project} do
      pg = playground_fixture(%{user: user, org: org, project: project})

      assert [found] = Playgrounds.list_playgrounds(project.id)
      assert found.id == pg.id
    end

    test "does not return playgrounds from other projects", %{
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})
      _pg = playground_fixture(%{user: user, org: org, project: project})

      assert [] = Playgrounds.list_playgrounds(other_project.id)
    end
  end

  describe "get_playground/2" do
    test "returns the playground for a project" do
      pg = playground_fixture()
      assert found = Playgrounds.get_playground(pg.project_id, pg.id)
      assert found.id == pg.id
    end

    test "returns nil for wrong project" do
      pg = playground_fixture()
      assert nil == Playgrounds.get_playground(Ecto.UUID.generate(), pg.id)
    end
  end

  describe "get_playground_by_slug/2" do
    test "returns the playground by slug" do
      pg = playground_fixture()
      assert found = Playgrounds.get_playground_by_slug(pg.project_id, pg.slug)
      assert found.id == pg.id
    end
  end

  describe "update_playground/2" do
    test "updates name and code" do
      pg = playground_fixture()

      assert {:ok, updated} =
               Playgrounds.update_playground(pg, %{name: "Updated", code: "IO.puts(:hello)"})

      assert updated.name == "Updated"
      assert updated.code == "IO.puts(:hello)"
    end

    test "slug is immutable on update" do
      pg = playground_fixture()
      original_slug = pg.slug

      assert {:ok, updated} = Playgrounds.update_playground(pg, %{name: "New Name"})
      assert updated.slug == original_slug
    end
  end

  describe "delete_playground/1" do
    test "deletes the playground" do
      pg = playground_fixture()
      assert {:ok, %Playground{}} = Playgrounds.delete_playground(pg)
      assert nil == Playgrounds.get_playground(pg.project_id, pg.id)
    end
  end

  describe "change_playground/2" do
    test "returns a changeset" do
      pg = playground_fixture()
      assert %Ecto.Changeset{} = Playgrounds.change_playground(pg)
    end
  end
end
