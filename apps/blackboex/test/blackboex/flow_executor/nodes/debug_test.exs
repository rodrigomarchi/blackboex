defmodule Blackboex.FlowExecutor.Nodes.DebugTest do
  use Blackboex.DataCase, async: false

  import ExUnit.CaptureLog

  alias Blackboex.FlowExecutor.Nodes.Debug

  describe "run/3" do
    test "passes input through unchanged (pass-through)" do
      args = %{prev_result: %{output: %{"data" => "hello"}, state: %{"count" => 1}}}
      opts = [timeout_ms: 5_000]

      assert {:ok, result} = Debug.run(args, %{}, opts)
      assert result.output == %{"data" => "hello"}
      assert result.state == %{"count" => 1}
    end

    test "evaluates expression and stores in state under state_key" do
      args = %{prev_result: %{output: %{"x" => 42}, state: %{}}}

      opts = [
        expression: ~s|%{"input_x" => input["x"], "at" => "checkpoint"}|,
        state_key: "debug_1",
        timeout_ms: 5_000
      ]

      assert {:ok, result} = Debug.run(args, %{}, opts)
      assert result.output == %{"x" => 42}
      assert result.state["debug_1"]["input_x"] == 42
      assert result.state["debug_1"]["at"] == "checkpoint"
    end

    test "logs at warning level when configured" do
      args = %{prev_result: %{output: "test", state: %{}}}
      opts = [expression: ~s|"warn msg"|, log_level: :warning, timeout_ms: 5_000]

      log =
        capture_log([level: :warning], fn ->
          Debug.run(args, %{}, opts)
        end)

      assert log =~ "warn msg"
    end

    test "uses default state_key 'debug' when not specified" do
      args = %{prev_result: %{output: %{}, state: %{}}}
      opts = [expression: ~s|"val"|, timeout_ms: 5_000]

      assert {:ok, result} = Debug.run(args, %{}, opts)
      assert result.state["debug"] == "val"
    end

    test "without expression, passes input through and does not modify state" do
      args = %{prev_result: %{output: %{"a" => 1}, state: %{"existing" => true}}}
      opts = [timeout_ms: 5_000]

      assert {:ok, result} = Debug.run(args, %{}, opts)
      assert result.output == %{"a" => 1}
      assert result.state == %{"existing" => true}
    end

    test "handles expression evaluation error gracefully" do
      args = %{prev_result: %{output: %{}, state: %{}}}
      opts = [expression: "raise \"boom\"", timeout_ms: 5_000]

      assert {:ok, result} = Debug.run(args, %{}, opts)
      assert result.output == %{}
      assert result.state["debug"] =~ "boom"
    end
  end
end
