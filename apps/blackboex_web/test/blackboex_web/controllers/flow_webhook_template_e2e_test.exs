defmodule BlackboexWeb.FlowWebhookTemplateE2eTest do
  @moduledoc """
  E2E tests for flow webhook execution using the Hello World template.
  Tests the full HTTP path: POST /webhook/:token → execute → response.
  """

  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  setup do
    {user, org} = Blackboex.OrganizationsFixtures.user_and_org_fixture()
    flow = flow_from_template_fixture(%{user: user, org: org})
    {:ok, flow} = Flows.activate_flow(flow)
    %{user: user, org: org, flow: flow}
  end

  describe "POST /webhook/:token — sync via template" do
    test "email route returns 200 with correct output", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{
          "name" => "João",
          "email" => "joao@test.com"
        })

      resp = json_response(conn, 200)
      assert resp["execution_id"]
      assert resp["duration_ms"] >= 0

      # Output is the mapped response from End (Email) node
      # response_mapping: delivered_via→channel, email→to, greeting→message
      output = resp["output"]
      assert output["channel"] == "email"
      assert output["to"] == "joao@test.com"
      assert output["message"] == "Hello, João!"
    end

    test "phone route returns 200 with mapped response", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{
          "name" => "Maria",
          "phone" => "11999887766"
        })

      resp = json_response(conn, 200)
      # Output is the mapped response from End (Phone) node
      output = resp["output"]
      assert output["channel"] == "phone"
      assert output["to"] == "11999887766"
      assert output["message"] == "Hello, Maria!"
    end

    test "no contact returns 200 with error in output (pass-through, no mapping)", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"name" => "Ana"})

      resp = json_response(conn, 200)
      # End (Error) has no response_mapping — pass-through from elixir_code output
      output = resp["output"]
      assert output["error"] == "no contact info provided"
    end

    test "missing name returns 422 with schema validation error", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{"phone" => "123"})

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "name"
      assert resp["execution_id"]
    end

    test "creates FlowExecution with correct records", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{
          "name" => "Test",
          "email" => "t@test.com"
        })

      resp = json_response(conn, 200)
      execution = FlowExecutions.get_execution(resp["execution_id"])

      assert execution.status == "completed"
      assert execution.input == %{"name" => "Test", "email" => "t@test.com"}
      assert length(execution.node_executions) >= 6
    end
  end

  describe "POST /webhook/:token — async via template" do
    setup %{flow: flow} do
      # Set the start node to async mode
      definition = flow.definition

      nodes =
        Enum.map(definition["nodes"], fn
          %{"type" => "start"} = node ->
            put_in(node, ["data", "execution_mode"], "async")

          node ->
            node
        end)

      {:ok, flow} = Flows.update_definition(flow, %{definition | "nodes" => nodes})
      %{flow: flow}
    end

    test "returns 202 with execution_id", %{flow: flow} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/webhook/#{flow.webhook_token}", %{
          "name" => "Async Test",
          "email" => "async@test.com"
        })

      resp = json_response(conn, 202)
      assert resp["execution_id"]
      assert resp["status_url"] =~ "/api/v1/executions/"

      # Execution starts as pending
      execution = FlowExecutions.get_execution(resp["execution_id"])
      assert execution.status == "pending"

      # Execute the Oban job inline
      assert :ok =
               perform_job(Blackboex.Workers.FlowExecutionWorker, %{
                 execution_id: resp["execution_id"],
                 flow_id: flow.id
               })

      # Verify execution completed
      execution = FlowExecutions.get_execution(resp["execution_id"])
      assert execution.status == "completed"
    end
  end
end
