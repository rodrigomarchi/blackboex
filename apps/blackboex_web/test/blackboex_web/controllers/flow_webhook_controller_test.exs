defmodule BlackboexWeb.FlowWebhookControllerTest do
  use BlackboexWeb.ConnCase, async: true

  describe "POST /webhook/:token" do
    setup [:setup_org_and_flow]

    test "returns 200 with output for sync flow", %{flow: flow} do
      flow = set_flow_active(flow, "sync")

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"name" => "hello"})

      resp = json_response(conn, 200)
      assert resp["execution_id"]
      assert resp["duration_ms"]
      assert resp["output"]
    end

    test "returns 404 for invalid token" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/invalid-token-xyz", %{})

      assert json_response(conn, 404) == %{"error" => "not found"}
    end

    test "returns 422 for archived flow", %{flow: flow} do
      {:ok, flow} = Blackboex.Flows.update_flow(flow, %{status: "archived"})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{})

      resp = json_response(conn, 422)
      assert resp["error"] =~ "not active"
    end

    test "returns 422 for draft flow", %{flow: flow} do
      flow = set_flow_definition(flow, "sync")
      # flow is draft by default
      assert flow.status == "draft"

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{})

      resp = json_response(conn, 422)
      assert resp["error"] =~ "not active"
    end

    test "returns 202 for async flow", %{flow: flow} do
      flow = set_flow_active(flow, "async")

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"name" => "hello"})

      resp = json_response(conn, 202)
      assert resp["execution_id"]
      assert resp["status_url"] =~ "/api/v1/executions/"
    end

    test "returns 422 with error when code raises", %{flow: flow} do
      flow = set_flow_active_with_bad_code(flow)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"name" => "test"})

      resp = json_response(conn, 422)
      assert resp["error"]
      assert resp["execution_id"]
    end

    test "handles empty JSON body gracefully", %{flow: flow} do
      flow = set_flow_active(flow, "sync")

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{})

      # Should still execute (empty input is valid)
      resp = json_response(conn, 200)
      assert resp["execution_id"]
    end

    test "FlowExecution criada tem project_id preenchido", %{flow: flow, org: _org} do
      flow = set_flow_active(flow, "sync")

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"input" => "test"})

      resp = json_response(conn, 200)
      assert exec_id = resp["execution_id"]

      execution = Blackboex.FlowExecutions.get_execution(exec_id)
      assert execution.project_id == flow.project_id
    end
  end

  defp setup_org_and_flow(_context) do
    {user, org} = Blackboex.OrganizationsFixtures.user_and_org_fixture()
    flow = flow_fixture(%{user: user, org: org})
    %{user: user, org: org, flow: flow}
  end

  defp set_flow_active(flow, execution_mode) do
    flow = set_flow_definition(flow, execution_mode)
    {:ok, flow} = Blackboex.Flows.update_flow(flow, %{status: "active"})
    flow
  end

  defp set_flow_definition(flow, execution_mode) do
    definition = %{
      "version" => "1.0",
      "nodes" => [
        %{
          "id" => "n1",
          "type" => "start",
          "data" => %{"execution_mode" => execution_mode},
          "position" => %{"x" => 0, "y" => 0}
        },
        %{
          "id" => "n2",
          "type" => "end",
          "data" => %{},
          "position" => %{"x" => 200, "y" => 0}
        }
      ],
      "edges" => [
        %{
          "id" => "e1",
          "source" => "n1",
          "source_port" => 0,
          "target" => "n2",
          "target_port" => 0
        }
      ]
    }

    {:ok, flow} = Blackboex.Flows.update_definition(flow, definition)
    flow
  end

  defp set_flow_active_with_bad_code(flow) do
    definition = %{
      "version" => "1.0",
      "nodes" => [
        %{
          "id" => "n1",
          "type" => "start",
          "data" => %{"execution_mode" => "sync"},
          "position" => %{"x" => 0, "y" => 0}
        },
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "data" => %{"code" => ~s|raise "boom"|},
          "position" => %{"x" => 200, "y" => 0}
        },
        %{
          "id" => "n3",
          "type" => "end",
          "data" => %{},
          "position" => %{"x" => 400, "y" => 0}
        }
      ],
      "edges" => [
        %{
          "id" => "e1",
          "source" => "n1",
          "source_port" => 0,
          "target" => "n2",
          "target_port" => 0
        },
        %{
          "id" => "e2",
          "source" => "n2",
          "source_port" => 0,
          "target" => "n3",
          "target_port" => 0
        }
      ]
    }

    {:ok, flow} = Blackboex.Flows.update_definition(flow, definition)
    {:ok, flow} = Blackboex.Flows.update_flow(flow, %{status: "active"})
    flow
  end
end
