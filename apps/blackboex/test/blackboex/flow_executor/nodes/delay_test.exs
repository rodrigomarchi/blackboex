defmodule Blackboex.FlowExecutor.Nodes.DelayTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.Delay

  describe "run/3" do
    test "delays for specified duration and passes input through unchanged" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [duration_ms: 5]

      t0 = System.monotonic_time(:millisecond)
      assert {:ok, %{output: "hello"}} = Delay.run(args, %{}, opts)
      elapsed = System.monotonic_time(:millisecond) - t0

      assert elapsed >= 5
    end

    test "adds delayed_ms to state" do
      args = %{prev_result: %{output: 42, state: %{}}}
      opts = [duration_ms: 1]

      assert {:ok, %{output: 42, state: %{"delayed_ms" => 1}}} = Delay.run(args, %{}, opts)
    end

    test "caps duration at max_duration_ms option" do
      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [duration_ms: 10_000, max_duration_ms: 5]

      assert {:ok, %{output: "data", state: %{"delayed_ms" => 5}}} = Delay.run(args, %{}, opts)
    end

    test "caps duration at absolute max (300_000ms)" do
      args = %{prev_result: %{output: "data", state: %{}}}
      # max_duration_ms and duration_ms both exceed the absolute cap; absolute_max_ms
      # is set to a small value so the test completes quickly while still exercising
      # the absolute cap code path.
      opts = [duration_ms: 400_000, max_duration_ms: 400_000, absolute_max_ms: 2]

      assert {:ok, %{output: "data", state: %{"delayed_ms" => 2}}} =
               Delay.run(args, %{}, opts)
    end

    test "works with zero duration" do
      args = %{prev_result: %{output: "zero", state: %{}}}
      opts = [duration_ms: 0]

      assert {:ok, %{output: "zero", state: %{"delayed_ms" => 0}}} = Delay.run(args, %{}, opts)
    end

    test "clamps negative duration to zero" do
      args = %{prev_result: %{output: "neg", state: %{}}}
      opts = [duration_ms: -100]

      assert {:ok, %{output: "neg", state: %{"delayed_ms" => 0}}} = Delay.run(args, %{}, opts)
    end

    test "preserves existing state keys" do
      args = %{prev_result: %{output: "x", state: %{"existing_key" => "value"}}}
      opts = [duration_ms: 1]

      assert {:ok, %{state: %{"existing_key" => "value", "delayed_ms" => 1}}} =
               Delay.run(args, %{}, opts)
    end

    test "falls back to input key when prev_result not present" do
      args = %{input: "start"}
      opts = [duration_ms: 1]

      assert {:ok, %{output: "start", state: %{"delayed_ms" => 1}}} = Delay.run(args, %{}, opts)
    end
  end
end
