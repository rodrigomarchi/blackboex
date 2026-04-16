defmodule Blackboex.PagesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Pages
  alias Blackboex.Pages.Page

  setup [:create_user_and_org]

  describe "create_page/1" do
    setup [:create_project]

    test "creates a page with valid attrs", %{org: org, project: project, user: user} do
      attrs = %{
        title: "Getting Started Guide",
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, %Page{} = page} = Pages.create_page(attrs)
      assert page.title == "Getting Started Guide"
      assert page.status == "draft"
      assert page.content == ""
      assert page.project_id == project.id
      assert page.organization_id == org.id
      assert page.user_id == user.id
      assert page.slug =~ ~r/^getting-started-guide-[a-z0-9]{6}$/
    end

    test "fails without required fields" do
      assert {:error, changeset} = Pages.create_page(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates content max length", %{org: org, project: project, user: user} do
      attrs = %{
        title: "Big Page",
        content: String.duplicate("a", 1_048_577),
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:error, changeset} = Pages.create_page(attrs)
      assert %{content: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most"
    end

    test "enforces unique slug per project", %{org: org, project: project, user: user} do
      page = page_fixture(%{user: user, org: org, project: project, title: "My Page"})

      attrs = %{
        title: "Another Page",
        slug: page.slug,
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:error, changeset} = Pages.create_page(attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_pages/1" do
    setup [:create_project]

    test "returns pages for a project", %{user: user, org: org, project: project} do
      page = page_fixture(%{user: user, org: org, project: project})

      assert [found] = Pages.list_pages(project.id)
      assert found.id == page.id
    end

    test "does not return pages from other projects", %{user: user, org: org, project: project} do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})
      _page = page_fixture(%{user: user, org: org, project: project})

      assert [] = Pages.list_pages(other_project.id)
    end
  end

  describe "list_pages/2 with search" do
    setup [:create_project]

    test "filters pages by title", %{user: user, org: org, project: project} do
      page_fixture(%{user: user, org: org, project: project, title: "Architecture Guide"})
      page_fixture(%{user: user, org: org, project: project, title: "Setup Notes"})

      results = Pages.list_pages(project.id, search: "Architecture")
      assert length(results) == 1
      assert hd(results).title == "Architecture Guide"
    end
  end

  describe "get_page/2" do
    test "returns the page for a project" do
      page = page_fixture()
      assert found = Pages.get_page(page.project_id, page.id)
      assert found.id == page.id
    end

    test "returns nil for wrong project" do
      page = page_fixture()
      assert nil == Pages.get_page(Ecto.UUID.generate(), page.id)
    end
  end

  describe "get_page_by_slug/2" do
    test "returns the page by slug" do
      page = page_fixture()
      assert found = Pages.get_page_by_slug(page.project_id, page.slug)
      assert found.id == page.id
    end
  end

  describe "update_page/2" do
    test "updates title and content" do
      page = page_fixture()

      assert {:ok, updated} =
               Pages.update_page(page, %{title: "Updated Title", content: "# Hello"})

      assert updated.title == "Updated Title"
      assert updated.content == "# Hello"
    end

    test "slug is immutable on update" do
      page = page_fixture()
      original_slug = page.slug

      assert {:ok, updated} = Pages.update_page(page, %{title: "New Title"})
      assert updated.slug == original_slug
    end

    test "updates status" do
      page = page_fixture()
      assert {:ok, updated} = Pages.update_page(page, %{status: "published"})
      assert updated.status == "published"
    end
  end

  describe "delete_page/1" do
    test "deletes the page" do
      page = page_fixture()
      assert {:ok, %Page{}} = Pages.delete_page(page)
      assert nil == Pages.get_page(page.project_id, page.id)
    end
  end

  describe "change_page/2" do
    test "returns a changeset" do
      page = page_fixture()
      assert %Ecto.Changeset{} = Pages.change_page(page)
    end
  end
end
