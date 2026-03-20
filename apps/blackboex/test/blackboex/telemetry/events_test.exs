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
