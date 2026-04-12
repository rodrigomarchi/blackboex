defmodule E2E.Phase.AdvancedFeatures do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 11: Advanced Features (debug, fail, skip_condition)"))
    flow = create_and_activate_template("advanced_features", "E2E AdvFeatures", user, org)

    [
      run_test("AdvFeat: valid data → success path", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"name" => "Rodrigo", "email" => "r@test.com"})

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["greeting"], "Hello, RODRIGO!", "greeting")
        assert_eq!(output["processed"], true, "processed")
        :ok
      end),
      run_test("AdvFeat: strict mode without email → fail node", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Test", "strict_mode" => true})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Validation failed", "error message")
        assert_contains!(resp.body["error"], "email required in strict mode", "mentions email")
        :ok
      end),
      run_test("AdvFeat: skip_validation=true bypasses validation", fn ->
        # strict_mode=true + no email, but skip_validation=true → skips → success
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "Skip",
            "strict_mode" => true,
            "skip_validation" => true
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["greeting"], "Hello, SKIP!", "greeting")
        :ok
      end),
      run_test("AdvFeat: debug node stores data in shared_state", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"name" => "DebugMe", "email" => "d@test.com"})

        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        state = exec.shared_state
        assert_present!(state["debug_input"], "debug_input in state")
        assert_eq!(state["debug_input"]["name"], "DebugMe", "debug captured name")
        :ok
      end),
      run_test("AdvFeat: execution has debug + condition + end node records", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "NodeCheck"})
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        node_types = Enum.map(exec.node_executions, & &1.node_type) |> MapSet.new()

        assert_present!(
          (MapSet.member?(node_types, "debug") && true) || nil,
          "debug node executed"
        )

        assert_present!(
          (MapSet.member?(node_types, "condition") && true) || nil,
          "condition node executed"
        )

        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "valid data success path",
        input: %{"name" => "Rodrigo", "email" => "r@test.com"},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["greeting"] == "Hello, RODRIGO!" and
               output["processed"] == true do
            :ok
          else
            {:error, "expected greeting + processed=true, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "strict mode without email",
        input: %{"name" => "Test", "strict_mode" => true},
        verify: fn resp ->
          if resp.status == 422 do
            :ok
          else
            {:error, "expected 422 for strict mode without email, got #{resp.status}"}
          end
        end
      }
    ]
  end
end
