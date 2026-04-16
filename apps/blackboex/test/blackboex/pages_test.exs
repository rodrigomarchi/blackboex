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

  # ── Hierarchy ──────────────────────────────────────────────

  describe "create_page/1 with hierarchy" do
    setup [:create_project]

    test "creates page with parent_id", %{org: org, project: project, user: user} do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      attrs = %{
        title: "Child Page",
        parent_id: parent.id,
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, %Page{} = child} = Pages.create_page(attrs)
      assert child.parent_id == parent.id
    end

    test "auto-assigns position as last sibling", %{org: org, project: project, user: user} do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      {:ok, first} =
        Pages.create_page(%{
          title: "First",
          parent_id: parent.id,
          organization_id: org.id,
          project_id: project.id,
          user_id: user.id
        })

      {:ok, second} =
        Pages.create_page(%{
          title: "Second",
          parent_id: parent.id,
          organization_id: org.id,
          project_id: project.id,
          user_id: user.id
        })

      assert first.position == 0
      assert second.position == 1
    end

    test "creates root page when parent_id is nil", %{org: org, project: project, user: user} do
      {:ok, page} =
        Pages.create_page(%{
          title: "Root",
          organization_id: org.id,
          project_id: project.id,
          user_id: user.id
        })

      assert is_nil(page.parent_id)
      assert page.position == 0
    end
  end

  describe "list_page_tree/1" do
    setup [:create_project]

    test "returns empty list for project with no pages", %{project: project} do
      assert [] = Pages.list_page_tree(project.id)
    end

    test "returns flat root pages as single-level tree", %{
      user: user,
      org: org,
      project: project
    } do
      p1 = page_fixture(%{user: user, org: org, project: project, title: "Page A"})
      p2 = page_fixture(%{user: user, org: org, project: project, title: "Page B"})

      tree = Pages.list_page_tree(project.id)
      assert length(tree) == 2
      ids = Enum.map(tree, & &1.page.id)
      assert p1.id in ids
      assert p2.id in ids
      assert Enum.all?(tree, &(&1.children == []))
    end

    test "returns nested tree with children under parent", %{
      user: user,
      org: org,
      project: project
    } do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: parent.id
        })

      tree = Pages.list_page_tree(project.id)
      assert [root_node] = tree
      assert root_node.page.id == parent.id
      assert [child_node] = root_node.children
      assert child_node.page.id == child.id
      assert child_node.children == []
    end

    test "returns 3-level deep tree", %{user: user, org: org, project: project} do
      root = page_fixture(%{user: user, org: org, project: project, title: "Root"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: root.id
        })

      grandchild =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Grandchild",
          parent_id: child.id
        })

      tree = Pages.list_page_tree(project.id)
      assert [root_node] = tree
      assert root_node.page.id == root.id
      assert [child_node] = root_node.children
      assert child_node.page.id == child.id
      assert [gc_node] = child_node.children
      assert gc_node.page.id == grandchild.id
    end

    test "orders siblings by position", %{user: user, org: org, project: project} do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      _c1 =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "First",
          parent_id: parent.id
        })

      _c2 =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Second",
          parent_id: parent.id
        })

      tree = Pages.list_page_tree(project.id)
      [root_node] = tree
      titles = Enum.map(root_node.children, & &1.page.title)
      assert titles == ["First", "Second"]
    end

    test "scopes tree to project", %{user: user, org: org, project: project} do
      page_fixture(%{user: user, org: org, project: project, title: "In Project"})
      other_project = project_fixture(%{user: user, org: org, name: "Other"})
      page_fixture(%{user: user, org: org, project: other_project, title: "Other Project"})

      tree = Pages.list_page_tree(project.id)
      assert length(tree) == 1
      assert hd(tree).page.title == "In Project"
    end
  end

  describe "move_page/3" do
    setup [:create_project]

    test "moves page to new parent", %{user: user, org: org, project: project} do
      parent_a = page_fixture(%{user: user, org: org, project: project, title: "Parent A"})
      parent_b = page_fixture(%{user: user, org: org, project: project, title: "Parent B"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: parent_a.id
        })

      assert {:ok, moved} = Pages.move_page(child, parent_b.id, 0)
      assert moved.parent_id == parent_b.id
      assert moved.position == 0
    end

    test "moves page to root", %{user: user, org: org, project: project} do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: parent.id
        })

      assert {:ok, moved} = Pages.move_page(child, nil, 0)
      assert is_nil(moved.parent_id)
    end

    test "rejects self-parenting", %{user: user, org: org, project: project} do
      page = page_fixture(%{user: user, org: org, project: project, title: "Self"})

      assert {:error, :self_parent} = Pages.move_page(page, page.id, 0)
    end

    test "rejects move that would exceed depth limit of 5", %{
      user: user,
      org: org,
      project: project
    } do
      # Build a chain of depth 4: l1 > l2 > l3 > l4
      l1 = page_fixture(%{user: user, org: org, project: project, title: "L1"})
      l2 = page_fixture(%{user: user, org: org, project: project, title: "L2", parent_id: l1.id})
      l3 = page_fixture(%{user: user, org: org, project: project, title: "L3", parent_id: l2.id})
      l4 = page_fixture(%{user: user, org: org, project: project, title: "L4", parent_id: l3.id})

      # A separate chain: a1 > a2
      a1 = page_fixture(%{user: user, org: org, project: project, title: "A1"})
      _a2 = page_fixture(%{user: user, org: org, project: project, title: "A2", parent_id: a1.id})

      # Moving a1 (which has a child) under l4 would make depth 6: l1>l2>l3>l4>a1>a2
      assert {:error, :max_depth_exceeded} = Pages.move_page(a1, l4.id, 0)
    end

    test "rejects circular reference", %{user: user, org: org, project: project} do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: parent.id
        })

      # Moving parent under its own child creates a cycle
      assert {:error, :circular_reference} = Pages.move_page(parent, child.id, 0)
    end
  end

  describe "delete_page/1 with children" do
    setup [:create_project]

    test "children become root pages after parent deleted", %{
      user: user,
      org: org,
      project: project
    } do
      parent = page_fixture(%{user: user, org: org, project: project, title: "Parent"})

      child =
        page_fixture(%{
          user: user,
          org: org,
          project: project,
          title: "Child",
          parent_id: parent.id
        })

      assert {:ok, _} = Pages.delete_page(parent)

      reloaded = Pages.get_page(project.id, child.id)
      assert is_nil(reloaded.parent_id)
    end
  end
end
