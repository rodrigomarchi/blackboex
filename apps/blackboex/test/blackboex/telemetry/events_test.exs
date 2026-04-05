defmodule Blackboex.Telemetry.EventsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Telemetry.Events

  setup do
    test_pid = self()
    handler_id = "test-handler-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    %{test_pid: test_pid, handler_id: handler_id}
  end

  describe "emit_api_request/1" do
    test "emits [:blackboex, :api, :request] event with correct data", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :api, :request],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_api_request(%{
        duration_ms: 42,
        api_id: "api-123",
        method: "GET",
        status_code: 200
      })

      assert_receive {:telemetry, [:blackboex, :api, :request], measurements, metadata}
      assert measurements.duration == 42
      assert metadata.api_id == "api-123"
      assert metadata.method == "GET"
      assert metadata.status == 200
    end
  end

  describe "emit_llm_call/1" do
    test "emits [:blackboex, :llm, :call] event with tokens", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :llm, :call],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_llm_call(%{
        duration_ms: 1500,
        input_tokens: 100,
        output_tokens: 200,
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      })

      assert_receive {:telemetry, [:blackboex, :llm, :call], measurements, metadata}
      assert measurements.duration == 1500
      assert measurements.input_tokens == 100
      assert measurements.output_tokens == 200
      assert metadata.provider == "anthropic"
      assert metadata.model == "claude-sonnet-4-20250514"
    end

    test "defaults missing tokens to 0", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :llm, :call],
        fn _event, measurements, _metadata, _config ->
          send(ctx.test_pid, {:telemetry_measurements, measurements})
        end,
        nil
      )

      Events.emit_llm_call(%{duration_ms: 100, provider: "openai", model: "gpt-4"})

      assert_receive {:telemetry_measurements, measurements}
      assert measurements.input_tokens == 0
      assert measurements.output_tokens == 0
    end
  end

  describe "emit_codegen/1" do
    test "emits [:blackboex, :codegen, :generate] event", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :codegen, :generate],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_codegen(%{
        duration_ms: 3000,
        template_type: :crud,
        description_length: 150
      })

      assert_receive {:telemetry, [:blackboex, :codegen, :generate], measurements, metadata}
      assert measurements.duration == 3000
      assert metadata.template_type == :crud
      assert metadata.description_length == 150
    end
  end

  describe "emit_compile/1" do
    test "emits [:blackboex, :codegen, :compile] event", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :codegen, :compile],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_compile(%{duration_ms: 50, api_id: "api-456", success: true})

      assert_receive {:telemetry, [:blackboex, :codegen, :compile], measurements, metadata}
      assert measurements.duration == 50
      assert metadata.api_id == "api-456"
      assert metadata.success == true
    end
  end

  describe "emit_sandbox_execute/1" do
    test "emits [:blackboex, :sandbox, :execute] event", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :sandbox, :execute],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_sandbox_execute(%{duration_ms: 200, api_id: "api-789"})

      assert_receive {:telemetry, [:blackboex, :sandbox, :execute], measurements, metadata}
      assert measurements.duration == 200
      assert metadata.api_id == "api-789"
    end
  end

  describe "emit_agent_run/1" do
    test "emits [:blackboex, :agent, :run] with all fields", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :agent, :run],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_agent_run(%{
        duration_ms: 5000,
        iteration_count: 3,
        cost_cents: 12,
        run_id: "run-1",
        run_type: "kickoff",
        status: "completed"
      })

      assert_receive {:telemetry, [:blackboex, :agent, :run], measurements, metadata}
      assert measurements.duration == 5000
      assert measurements.iteration_count == 3
      assert measurements.cost_cents == 12
      assert metadata.run_id == "run-1"
      assert metadata.run_type == "kickoff"
      assert metadata.status == "completed"
    end

    test "defaults duration_ms, iteration_count, cost_cents to 0 when missing", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :agent, :run],
        fn _event, measurements, _metadata, _config ->
          send(ctx.test_pid, {:telemetry_measurements, measurements})
        end,
        nil
      )

      Events.emit_agent_run(%{run_id: "r", run_type: "fix", status: "error"})

      assert_receive {:telemetry_measurements, measurements}
      assert measurements.duration == 0
      assert measurements.iteration_count == 0
      assert measurements.cost_cents == 0
    end
  end

  describe "emit_agent_tool/1" do
    test "emits [:blackboex, :agent, :tool] with correct fields", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :agent, :tool],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_agent_tool(%{
        duration_ms: 75,
        tool_name: "http_request",
        success: true,
        run_id: "run-2"
      })

      assert_receive {:telemetry, [:blackboex, :agent, :tool], measurements, metadata}
      assert measurements.duration == 75
      assert metadata.tool_name == "http_request"
      assert metadata.success == true
      assert metadata.run_id == "run-2"
    end

    test "duration defaults to 0 when missing", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :agent, :tool],
        fn _event, measurements, _metadata, _config ->
          send(ctx.test_pid, {:telemetry_measurements, measurements})
        end,
        nil
      )

      Events.emit_agent_tool(%{tool_name: "t", success: false, run_id: "r"})

      assert_receive {:telemetry_measurements, measurements}
      assert measurements.duration == 0
    end
  end

  describe "emit_circuit_breaker/1" do
    test "emits [:blackboex, :circuit_breaker, :state_change] with state transition", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :circuit_breaker, :state_change],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_circuit_breaker(%{provider: "openai", from_state: :closed, to_state: :open})

      assert_receive {:telemetry, [:blackboex, :circuit_breaker, :state_change], measurements, metadata}
      assert measurements == %{}
      assert metadata.provider == "openai"
      assert metadata.from_state == :closed
      assert metadata.to_state == :open
    end
  end

  describe "emit_session_timeout/1" do
    test "emits [:blackboex, :agent, :session_timeout] with count 1 and run_id", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :agent, :session_timeout],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_session_timeout(%{run_id: "run-timeout"})

      assert_receive {:telemetry, [:blackboex, :agent, :session_timeout], measurements, metadata}
      assert measurements.count == 1
      assert metadata.run_id == "run-timeout"
    end
  end

  describe "emit_policy_denied/1" do
    test "emits [:blackboex, :policy, :denied] with action and user_id", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :policy, :denied],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_policy_denied(%{action: :create_api, user_id: "user-99"})

      assert_receive {:telemetry, [:blackboex, :policy, :denied], measurements, metadata}
      assert measurements.count == 1
      assert metadata.action == :create_api
      assert metadata.user_id == "user-99"
    end
  end

  describe "emit_rate_limit_rejected/1" do
    test "emits [:blackboex, :rate_limit, :rejected] with type and key", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :rate_limit, :rejected],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_rate_limit_rejected(%{type: :api_invocation, key: "api-key-123"})

      assert_receive {:telemetry, [:blackboex, :rate_limit, :rejected], measurements, metadata}
      assert measurements.count == 1
      assert metadata.type == :api_invocation
      assert metadata.key == "api-key-123"
    end
  end

  describe "emit_pool_saturation/1" do
    test "emits [:blackboex, :ecto, :pool_saturation] with queue_time_ms", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :ecto, :pool_saturation],
        fn event, measurements, metadata, _config ->
          send(ctx.test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Events.emit_pool_saturation(%{queue_time_ms: 250})

      assert_receive {:telemetry, [:blackboex, :ecto, :pool_saturation], measurements, metadata}
      assert measurements.queue_time_ms == 250
      assert metadata == %{}
    end
  end

  describe "safe_execute resilience" do
    test "does not crash caller when handler raises", ctx do
      :telemetry.attach(
        ctx.handler_id,
        [:blackboex, :api, :request],
        fn _event, _measurements, _metadata, _config ->
          raise "handler crash"
        end,
        nil
      )

      # Should not raise — safe_execute catches the error
      assert :ok =
               Events.emit_api_request(%{
                 duration_ms: 10,
                 api_id: "api-safe",
                 method: "GET",
                 status_code: 200
               })
    end
  end
end
