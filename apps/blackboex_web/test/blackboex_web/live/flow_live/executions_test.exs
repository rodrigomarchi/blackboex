defmodule BlackboexWeb.FlowLive.ExecutionsTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  alias Blackboex.FlowExecutor

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/flows/#{Ecto.UUID.generate()}/executions")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "shows empty state when no executions", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_fixture(%{user: user, org: org})

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/executions")
      assert html =~ "No executions yet"
    end

    test "lists executions for a flow", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:ok, _result} =
        FlowExecutor.execute_sync(flow, %{"name" => "Test", "email" => "t@t.com"})

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/executions")
      assert html =~ "completed"
      assert html =~ "Details"
    end

    test "shows failed execution", %{conn: conn, user: user} do
      [org | _] = Blackboex.Organizations.list_user_organizations(user)
      flow = flow_from_template_fixture(%{user: user, org: org})

      {:error, _} = FlowExecutor.execute_sync(flow, %{"phone" => "123"})

      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/executions")
      assert html =~ "failed"
    end
  end
end
