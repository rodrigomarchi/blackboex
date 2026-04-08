defmodule BlackboexWeb.FlowExecutionControllerTest do
  use BlackboexWeb.ConnCase, async: true

  describe "GET /api/v1/executions/:id" do
    setup [:register_and_log_in_user]

    setup %{conn: conn, user: user} do
      org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
      conn = Plug.Conn.put_session(conn, :organization_id, org.id)
      flow = flow_fixture(%{user: user, org: org})
      execution = flow_execution_fixture(%{flow: flow, input: %{"x" => 1}})
      %{conn: conn, org: org, flow: flow, execution: execution}
    end

    test "returns 200 with execution data", %{conn: conn, execution: execution} do
      conn = get(conn, "/api/v1/executions/#{execution.id}")

      resp = json_response(conn, 200)
      assert resp["data"]["id"] == execution.id
      assert resp["data"]["status"] == "pending"
      assert resp["data"]["input"] == %{"x" => 1}
    end

    test "returns 404 for non-existent execution", %{conn: conn} do
      conn = get(conn, "/api/v1/executions/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404) == %{"error" => "not found"}
    end

    test "returns 404 for execution from another org", %{conn: conn} do
      other_execution = flow_execution_fixture()
      conn = get(conn, "/api/v1/executions/#{other_execution.id}")
      assert json_response(conn, 404) == %{"error" => "not found"}
    end
  end

  describe "GET /api/v1/flows/:slug/executions" do
    setup [:register_and_log_in_user]

    setup %{conn: conn, user: user} do
      org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
      conn = Plug.Conn.put_session(conn, :organization_id, org.id)
      flow = flow_fixture(%{user: user, org: org, name: "My Test Flow"})
      _exec1 = flow_execution_fixture(%{flow: flow})
      _exec2 = flow_execution_fixture(%{flow: flow})
      %{conn: conn, org: org, flow: flow}
    end

    test "returns 200 with list of executions", %{conn: conn, flow: flow} do
      conn = get(conn, "/api/v1/flows/#{flow.slug}/executions")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 2
    end

    test "returns 404 for unknown slug", %{conn: conn} do
      conn = get(conn, "/api/v1/flows/nonexistent-slug/executions")
      assert json_response(conn, 404) == %{"error" => "flow not found"}
    end
  end
end
