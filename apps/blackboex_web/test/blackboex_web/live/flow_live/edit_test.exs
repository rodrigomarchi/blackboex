defmodule BlackboexWeb.FlowLive.EditTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/flows/#{Ecto.UUID.generate()}/edit")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "mounts with flow data", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Editor Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "Editor Flow"
      assert html =~ "draft"
      assert html =~ "drawflow-canvas"
    end

    test "redirects when flow not found", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/flows/#{Ecto.UUID.generate()}/edit")
        |> follow_redirect(conn)

      assert html =~ "Flow not found"
    end

    test "shows node palette", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Palette Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")
      assert html =~ "Start"
      assert html =~ "Elixir Code"
      assert html =~ "Condition"
      assert html =~ "End"
    end

    test "saves definition via event", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)

      {:ok, flow} =
        Blackboex.Flows.create_flow(%{
          name: "Save Flow",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      definition = %{"drawflow" => %{"Home" => %{"data" => %{"1" => %{"name" => "test"}}}}}

      render_hook(view, "save_definition", %{"definition" => definition})

      updated = Blackboex.Flows.get_flow(org.id, flow.id)
      assert updated.definition["drawflow"]["Home"]["data"]["1"]["name"] == "test"
    end
  end
end
