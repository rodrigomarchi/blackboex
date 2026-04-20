defmodule BlackboexWeb.Components.SidebarTreeComponentTest do
  @moduledoc false

  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias Blackboex.{Accounts, Apis, Flows, Organizations, Pages, Playgrounds, Projects}
  alias Blackboex.Accounts.Scope
  alias BlackboexWeb.Components.SidebarTreeComponent

  # Builds a scope with org and membership attached, given user + org.
  defp scoped(user, org) do
    membership = Organizations.get_user_membership(org, user)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  describe "render/1" do
    setup :register_and_log_in_user

    test "renders placeholder with data-testid", %{scope: scope} do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-1",
          current_scope: scope,
          current_path: "/",
          collapsed: false
        )

      assert html =~ ~s(data-testid="sidebar-tree")
      assert html =~ ~s(id="tree-1")
    end

    test "reads expanded preference for the user without crashing", %{scope: scope, user: user} do
      {:ok, _} =
        Accounts.update_user_preference(user, ["sidebar_tree", "expanded"], [
          "project:abc"
        ])

      reloaded = Blackboex.Repo.get!(Blackboex.Accounts.User, user.id)
      scope = %{scope | user: reloaded}

      html =
        render_component(SidebarTreeComponent,
          id: "tree-2",
          current_scope: scope,
          current_path: "/",
          collapsed: false
        )

      assert html =~ ~s(data-testid="sidebar-tree")
    end

    test "renders without crashing when current_scope is nil" do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-3",
          current_scope: nil,
          current_path: "/",
          collapsed: false
        )

      assert html =~ ~s(data-testid="sidebar-tree")
    end
  end

  describe "real render" do
    setup [:register_and_log_in_user, :create_org_and_api]

    # Builds a scope with org+membership from the test context %{user, org}.
    setup %{user: user, org: org} do
      %{scope: scoped(user, org)}
    end

    test "renders 'No projects yet.' when scope has no organization", %{user: user} do
      # A scope with organization: nil has no projects to show
      no_org_scope = Scope.for_user(user)

      html =
        render_component(SidebarTreeComponent,
          id: "tree-empty",
          current_scope: no_org_scope,
          current_path: "/",
          collapsed: false
        )

      assert html =~ "No projects yet"
    end

    test "renders project name in sidebar", %{scope: scope, project: project} do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-projects",
          current_scope: scope,
          current_path: "/",
          collapsed: false
        )

      assert html =~ project.name
    end

    test "shows APIs group label in expanded project", %{scope: scope, project: project} do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-expanded",
          current_scope: scope,
          current_path: "/",
          collapsed: false,
          expanded: ["project:#{project.id}"],
          tree_children: %{}
        )

      assert html =~ "Pages"
      assert html =~ "APIs"
      assert html =~ "Flows"
      assert html =~ "Playgrounds"
    end

    test "leaf node link contains org_slug and project_slug for api", %{
      scope: scope,
      project: project,
      api: api
    } do
      apis = [api]

      html =
        render_component(SidebarTreeComponent,
          id: "tree-leaf",
          current_scope: scope,
          current_path: "/",
          collapsed: false,
          expanded: ["project:#{project.id}", "apis:#{project.id}"],
          tree_children: %{"apis:#{project.id}" => apis}
        )

      assert html =~ scope.organization.slug
      assert html =~ project.slug
      assert html =~ api.slug
    end

    test "auto-expands path to current project and group", %{
      scope: scope,
      project: project
    } do
      current_path = "/orgs/#{scope.organization.slug}/projects/#{project.slug}/apis"

      html =
        render_component(SidebarTreeComponent,
          id: "tree-auto",
          current_scope: scope,
          current_path: current_path,
          collapsed: false
        )

      # auto_expand_from_path should expand the project and apis group
      assert html =~ "Pages"
      assert html =~ "APIs"
    end

    test "current_scope nil does not crash" do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-nil",
          current_scope: nil,
          current_path: "/",
          collapsed: false
        )

      assert html =~ ~s(data-testid="sidebar-tree")
      assert html =~ "No projects yet"
    end

    @tag :liveview
    test "expand_node event toggles project open",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _html} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{
            "user_id" => user.id,
            "org_id" => org.id
          }
        )

      # Before expand: group labels should not appear
      refute render(view) =~ "Pages"

      # Click expand on the project node
      view
      |> element(
        "[phx-value-type='project'][phx-value-id='#{project.id}']",
        project.name
      )
      |> render_click()

      # After expand: group labels should appear
      assert render(view) =~ "Pages"
      assert render(view) =~ "APIs"
    end
  end

  describe "rename" do
    setup [:register_and_log_in_user, :create_org_and_api]

    # Re-build scope with org+membership from test context
    setup %{user: user, org: org} do
      %{scope: scoped(user, org)}
    end

    @tag :liveview
    test "open_item_menu event sets open_menu_id",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand project and APIs group so leaf nodes are rendered
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      # Click ⋯ button on the leaf
      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Rename"
      assert html =~ "Delete"
    end

    @tag :liveview
    test "start_rename switches label to inline input",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='start_rename'][phx-value-id='#{api.id}']")
      |> render_click()

      html = render(view)
      assert html =~ ~s(name="value")
      assert html =~ api.name
    end

    @tag :liveview
    test "cancel_rename removes the inline input",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='start_rename'][phx-value-id='#{api.id}']")
      |> render_click()

      assert render(view) =~ ~s(name="value")

      view
      |> element("[phx-click='cancel_rename']")
      |> render_click()

      refute render(view) =~ ~s(name="value")
    end

    @tag :liveview
    test "submit_rename with valid name updates resource and refreshes tree",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='start_rename'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("form[phx-submit='submit_rename']")
      |> render_submit(%{type: "apis", _id: api.id, value: "Renamed API"})

      html = render(view)
      # Rename input should be gone
      refute html =~ ~s(name="value")
      # Updated name visible in tree
      assert html =~ "Renamed API"

      # Verify in DB
      updated = Apis.get_api(org.id, api.id)
      assert updated.name == "Renamed API"
    end

    @tag :liveview
    test "submit_rename with blank name shows error",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='start_rename'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("form[phx-submit='submit_rename']")
      |> render_submit(%{type: "apis", _id: api.id, value: "   "})

      html = render(view)
      assert html =~ "blank"
      # Input should still be visible
      assert html =~ ~s(name="value")
    end
  end

  describe "delete" do
    setup [:register_and_log_in_user, :create_org_and_api]

    # Re-build scope with org+membership from test context
    setup %{user: user, org: org} do
      %{scope: scoped(user, org)}
    end

    @tag :liveview
    test "open_delete_modal shows modal with confirm input",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_delete_modal'][phx-value-id='#{api.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Delete"
      assert html =~ api.name
      assert html =~ ~s(name="confirm")
    end

    @tag :liveview
    test "close_delete_modal hides modal",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_delete_modal'][phx-value-id='#{api.id}']")
      |> render_click()

      assert render(view) =~ ~s(name="confirm")

      view
      |> element("button[phx-click='close_delete_modal'][phx-target]")
      |> render_click()

      refute render(view) =~ ~s(name="confirm")
    end

    @tag :liveview
    test "confirm_delete with matching name deletes resource and refreshes tree",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_delete_modal'][phx-value-id='#{api.id}']")
      |> render_click()

      # Type the resource name to confirm
      view
      |> element("form[phx-change='update_delete_confirm']")
      |> render_change(%{confirm: api.name})

      view
      |> element("[phx-click='confirm_delete'][phx-target]")
      |> render_click()

      # Modal should be gone
      refute render(view) =~ ~s(name="confirm")

      # Resource deleted from DB
      assert Apis.get_api(org.id, api.id) == nil
    end

    @tag :liveview
    test "confirm_delete with mismatched confirm_text does NOT delete",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='expand_node'][phx-value-type='apis']")
      |> render_click()

      view
      |> element("[phx-click='open_item_menu'][phx-value-id='#{api.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_delete_modal'][phx-value-id='#{api.id}']")
      |> render_click()

      # Type wrong confirm text — button stays disabled (no click possible)
      # Verify the modal remains open (confirm text mismatch, button disabled)
      view
      |> element("form[phx-change='update_delete_confirm']")
      |> render_change(%{confirm: "wrong-name"})

      html = render(view)
      # Modal still visible with the mismatched input
      assert html =~ ~s(name="confirm")
      # Resource not deleted
      assert Apis.get_api(org.id, api.id) != nil
    end
  end

  describe "create resource modal" do
    setup [:register_and_log_in_user, :create_org_and_api]

    # Re-build scope with org+membership from test context
    setup %{user: user, org: org} do
      %{scope: scoped(user, org)}
    end

    test "open_create_modal renders modal for apis group",
         %{scope: scope, project: project} do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-modal",
          current_scope: scope,
          current_path: "/",
          collapsed: false,
          expanded: ["project:#{project.id}"],
          tree_children: %{},
          create_modal: %{type: "apis", project_id: project.id, parent_id: nil}
        )

      assert html =~ "Create APIs"
      assert html =~ ~s(name="type")
      assert html =~ ~s(value="apis")
    end

    test "group node renders + button when project is expanded",
         %{scope: scope, project: project} do
      html =
        render_component(SidebarTreeComponent,
          id: "tree-plus",
          current_scope: scope,
          current_path: "/",
          collapsed: false,
          expanded: ["project:#{project.id}"],
          tree_children: %{}
        )

      assert html =~ ~s(aria-label="Create APIs")
      assert html =~ ~s(aria-label="Create Pages")
      assert html =~ ~s(aria-label="Create Flows")
      assert html =~ ~s(aria-label="Create Playgrounds")
    end

    @tag :liveview
    test "open_create_modal event shows modal",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand project first
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      # Click the + button for apis group
      view
      |> element("[phx-click='open_create_modal'][phx-value-type='apis']")
      |> render_click()

      html = render(view)
      assert html =~ ~s(phx-submit="create_resource")
    end

    @tag :liveview
    test "close_create_modal event hides modal",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand and open modal
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='apis']")
      |> render_click()

      assert render(view) =~ ~s(phx-submit="create_resource")

      # Close it via the Cancel button (phx-target ensures it hits the component)
      view
      |> element("button[phx-click='close_create_modal'][phx-target]")
      |> render_click()

      refute render(view) =~ ~s(phx-submit="create_resource")
    end

    @tag :liveview
    test "create_resource creates an api and navigates",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand project and open modal
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='apis']")
      |> render_click()

      # Submit create_resource form; push_navigate returns {:error, {:live_redirect, ...}} in isolated mode
      result =
        view
        |> element("form[phx-submit='create_resource']")
        |> render_submit(%{type: "api", project_id: project.id, name: "My New API"})

      # Either a redirect happened (resource created) or HTML with no error
      assert match?({:error, {:live_redirect, _}}, result) or is_binary(result)

      # Verify the api was created in the database
      apis = Apis.list_for_project(project.id)
      assert Enum.any?(apis, &(&1.name == "My New API"))
    end

    @tag :liveview
    test "create_resource creates a flow and navigates",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='flows']")
      |> render_click()

      result =
        view
        |> element("form[phx-submit='create_resource']")
        |> render_submit(%{type: "flow", project_id: project.id, name: "My Flow"})

      assert match?({:error, {:live_redirect, _}}, result) or is_binary(result)

      flows = Flows.list_for_project(project.id)
      assert Enum.any?(flows, &(&1.name == "My Flow"))
    end

    @tag :liveview
    test "create_resource creates a page",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='pages']")
      |> render_click()

      result =
        view
        |> element("form[phx-submit='create_resource']")
        |> render_submit(%{type: "page", project_id: project.id, name: "My Page"})

      assert match?({:error, {:live_redirect, _}}, result) or is_binary(result)

      pages = Pages.list_root_pages_for_project(project.id)
      assert Enum.any?(pages, &(&1.title == "My Page"))
    end

    @tag :liveview
    test "create_resource creates a playground",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='playgrounds']")
      |> render_click()

      result =
        view
        |> element("form[phx-submit='create_resource']")
        |> render_submit(%{type: "playground", project_id: project.id, name: "My Playground"})

      assert match?({:error, {:live_redirect, _}}, result) or is_binary(result)

      playgrounds = Playgrounds.list_for_project(project.id)
      assert Enum.any?(playgrounds, &(&1.name == "My Playground"))
    end

    @tag :liveview
    test "create_resource with unknown type is rejected (no resource created)",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand project and open modal for apis, then submit with invalid type via form
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='apis']")
      |> render_click()

      # Submit with evil_type overriding the hidden input — component must reject via whitelist
      view
      |> element("form[phx-submit='create_resource']")
      |> render_submit(%{type: "evil_type", project_id: project.id, name: "Hacked"})

      # No new api should be created (only the original fixture api exists)
      assert Apis.list_for_project(project.id) |> length() == 1
    end

    @tag :liveview
    test "create_resource with blank name shows error and keeps modal open",
         %{conn: conn, user: user, org: org, project: project} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Expand project node and open create modal for apis
      view
      |> element("[phx-value-type='project'][phx-value-id='#{project.id}']")
      |> render_click()

      view
      |> element("[phx-click='open_create_modal'][phx-value-type='apis']")
      |> render_click()

      # Submit with a blank name — the api changeset validation will fail
      html =
        view
        |> element("form[phx-submit='create_resource']")
        |> render_submit(%{type: "api", project_id: project.id, name: ""})

      # Modal must still be visible
      assert html =~ ~s(phx-submit="create_resource")
      # Error paragraph must appear
      assert html =~ ~s(role="alert")
    end
  end

  describe "move_node" do
    setup [:register_and_log_in_user, :create_org_and_api]

    setup %{user: user, org: org} do
      %{scope: scoped(user, org)}
    end

    @tag :liveview
    test "move api between projects in same org succeeds",
         %{conn: conn, user: user, org: org, api: api} do
      # Create a second project in the same org
      {:ok, %{project: project2}} = Projects.create_project(org, user, %{name: "Project Two"})

      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[data-testid='sidebar-tree']")
      |> render_hook("move_node", %{
        "node_id" => api.id,
        "node_type" => "api",
        "new_parent_type" => "apis",
        "new_parent_id" => project2.id,
        "new_index" => 0
      })

      updated = Apis.get_api(org.id, api.id)
      assert updated.project_id == project2.id
    end

    @tag :liveview
    test "move api to another org is rejected",
         %{conn: conn, user: user, api: api} do
      # Create a second org for a different user
      other_user = user_fixture()

      {:ok, %{organization: other_org, project: other_project}} =
        Organizations.create_organization(other_user, %{
          name: "OtherOrg#{System.unique_integer()}"
        })

      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => api.organization_id}
        )

      view
      |> element("[data-testid='sidebar-tree']")
      |> render_hook("move_node", %{
        "node_id" => api.id,
        "node_type" => "api",
        "new_parent_type" => "apis",
        "new_parent_id" => other_project.id,
        "new_index" => 0
      })

      # Api should remain in original project (not moved to other org)
      still = Apis.get_api(api.organization_id, api.id)
      assert still.project_id == api.project_id
      _ = other_org
    end

    @tag :liveview
    test "move api to flows group (cross-type) is rejected",
         %{conn: conn, user: user, org: org, project: project, api: api} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[data-testid='sidebar-tree']")
      |> render_hook("move_node", %{
        "node_id" => api.id,
        "node_type" => "api",
        "new_parent_type" => "flows",
        "new_parent_id" => project.id,
        "new_index" => 0
      })

      # Api should be unchanged
      assert Apis.get_api(org.id, api.id) != nil
    end

    @tag :liveview
    test "move node with invalid params does not crash",
         %{conn: conn, user: user, org: org} do
      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      # Missing node_id — should not crash
      html =
        view
        |> element("[data-testid='sidebar-tree']")
        |> render_hook("move_node", %{
          "node_type" => "api",
          "new_parent_type" => "apis",
          "new_parent_id" => "some-id",
          "new_index" => 0
        })

      assert is_binary(html)
    end

    @tag :liveview
    test "rejected move does not crash the component",
         %{conn: conn, user: user, api: api} do
      # Move to a completely different org project → rejected
      other_user = user_fixture()

      {:ok, %{organization: _other_org, project: other_project}} =
        Organizations.create_organization(other_user, %{
          name: "OtherOrg#{System.unique_integer()}"
        })

      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => api.organization_id}
        )

      html =
        view
        |> element("[data-testid='sidebar-tree']")
        |> render_hook("move_node", %{
          "node_id" => api.id,
          "node_type" => "api",
          "new_parent_type" => "apis",
          "new_parent_id" => other_project.id,
          "new_index" => 0
        })

      # View should still render without crash
      assert is_binary(html)
    end

    @tag :liveview
    test "move flow between projects in same org succeeds",
         %{conn: conn, user: user, org: org, project: project} do
      flow = flow_fixture(%{organization_id: org.id, project_id: project.id, user_id: user.id})
      {:ok, %{project: project2}} = Projects.create_project(org, user, %{name: "Flow Dest"})

      {:ok, view, _} =
        live_isolated(conn, BlackboexWeb.Components.SidebarTreeTestWrapper,
          session: %{"user_id" => user.id, "org_id" => org.id}
        )

      view
      |> element("[data-testid='sidebar-tree']")
      |> render_hook("move_node", %{
        "node_id" => flow.id,
        "node_type" => "flow",
        "new_parent_type" => "flows",
        "new_parent_id" => project2.id,
        "new_index" => 0
      })

      updated = Flows.get_flow(org.id, flow.id)
      assert updated.project_id == project2.id
    end
  end
end
