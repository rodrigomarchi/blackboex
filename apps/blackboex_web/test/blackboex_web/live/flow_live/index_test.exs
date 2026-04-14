defmodule BlackboexWeb.FlowLive.IndexTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/flows")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "lists flows for the current org", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _flow} =
        Blackboex.Flows.create_flow(%{
          name: "My Test Flow",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "My Test Flow"
      assert html =~ "draft"
    end

    test "shows empty state when no flows", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "No flows"
    end

    test "has button to create new flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/flows")
      assert has_element?(view, "button[phx-click='open_create_modal']")
    end

    test "displays flow description when present", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _flow} =
        Blackboex.Flows.create_flow(%{
          name: "Described Flow",
          description: "Processes incoming webhooks",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows")
      assert html =~ "Processes incoming webhooks"
    end

    test "deletes a flow", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Delete Me",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows")
      assert render(view) =~ "Delete Me"

      # Delete is gated by a request_confirm modal in the UI. Fire the
      # confirmed "delete" event directly so this test stays coupled to the
      # real handler instead of the confirmation flow.
      render_click(view, "delete", %{"id" => flow.id})

      refute render(view) =~ "Delete Me"
    end

    test "create modal has template and blank tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/flows")

      # Fire the open_create_modal event directly — the page has more than
      # one "Create Flow" button (header + empty state) so an element
      # selector can't uniquely target one.
      render_click(view, "open_create_modal", %{})

      html = render(view)
      assert html =~ "From template"
      assert html =~ "Blank flow"
    end

    test "template tab shows Hello World template", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/flows")

      view |> element("header button[phx-click='open_create_modal']") |> render_click()
      view |> element("button[phx-value-mode='template']") |> render_click()

      html = render(view)
      assert html =~ "Hello World"
      assert html =~ "contact router"
    end

    test "creating from template creates flow with definition", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/flows")

      view |> element("header button[phx-click='open_create_modal']") |> render_click()
      view |> element("button[phx-value-mode='template']") |> render_click()
      view |> element("button[phx-value-id='hello_world']") |> render_click()

      view
      |> form("form[phx-submit='create_flow']", %{name: "Template Flow", description: ""})
      |> render_submit()

      # Should navigate to editor
      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/flows/.*/edit"
    end

    test "searches flows by name", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, _} =
        Blackboex.Flows.create_flow(%{
          name: "Payment Flow",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, _} =
        Blackboex.Flows.create_flow(%{
          name: "Auth Flow",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows")
      assert render(view) =~ "Payment Flow"
      assert render(view) =~ "Auth Flow"

      view
      |> form("form", %{search: "Payment"})
      |> render_change()

      assert render(view) =~ "Payment Flow"
      refute render(view) =~ "Auth Flow"
    end
  end
end
