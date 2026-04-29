defmodule E2E.Phase.HelloWorld do
  import E2E.Helpers

  def run(flow) do
    IO.puts(cyan("\n▸ Phase 1: Hello World Template"))

    [
      run_test("HW: email route", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"name" => "Rodrigo", "email" => "test@example.com"})

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["channel"], "email", "channel")
        assert_eq!(output["to"], "test@example.com", "to")
        assert_eq!(output["message"], "Hello, Rodrigo!", "message")
        assert_present!(resp.body["execution_id"], "execution_id")
        assert_gte!(resp.body["duration_ms"], 0, "duration_ms")
        :ok
      end),
      run_test("HW: phone route", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"name" => "Maria", "phone" => "11999887766"})

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["channel"], "phone", "channel")
        assert_eq!(output["to"], "11999887766", "to")
        assert_eq!(output["message"], "Hello, Maria!", "message")
        :ok
      end),
      run_test("HW: no-contact error", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Ana"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["error"], "no contact info provided", "error")
        :ok
      end),
      run_test("HW: schema validation (missing name)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"phone" => "123"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        assert_contains!(resp.body["error"], "name", "mentions name")
        assert_present!(resp.body["execution_id"], "execution_id")
        :ok
      end),
      run_test("HW: execution record persisted", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"name" => "Persist", "email" => "p@test.com"})

        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_eq!(exec.status, "completed", "execution status")
        assert_gte!(length(exec.node_executions), 5, "node executions count")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "email route",
        input: %{"name" => "Rodrigo", "email" => "stress@test.com"},
        verify: fn resp ->
          if resp.status == 200 and resp.body["output"]["channel"] == "email" and
               resp.body["output"]["message"] == "Hello, Rodrigo!" do
            :ok
          else
            {:error,
             "expected channel=email + message='Hello, Rodrigo!', got #{inspect(resp.body["output"])}"}
          end
        end
      },
      %{
        name: "phone route",
        input: %{"name" => "Maria", "phone" => "11999887766"},
        verify: fn resp ->
          if resp.status == 200 and resp.body["output"]["channel"] == "phone" do
            :ok
          else
            {:error, "expected channel=phone, got #{inspect(resp.body["output"])}"}
          end
        end
      },
      %{
        name: "schema error (missing name)",
        input: %{"phone" => "123"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
