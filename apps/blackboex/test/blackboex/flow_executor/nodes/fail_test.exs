defmodule Blackboex.FlowExecutor.Nodes.FailTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.Fail

  describe "run/3" do
    test "returns error with evaluated message" do
      args = %{prev_result: %{output: %{"reason" => "bad input"}, state: %{}}}
      opts = [message: ~S|"Error: #{input["reason"]}"|, timeout_ms: 5_000]

      assert {:error, msg} = Fail.run(args, %{}, opts)
      assert msg =~ "Error: bad input"
    end

    test "returns error with static message" do
      args = %{prev_result: %{output: %{}, state: %{}}}
      opts = [message: ~s|"Something went wrong"|, timeout_ms: 5_000]

      assert {:error, "Something went wrong"} = Fail.run(args, %{}, opts)
    end

    test "includes state snapshot when include_state is true" do
      args = %{prev_result: %{output: %{}, state: %{"user_id" => "123"}}}
      opts = [message: ~s|"fail"|, include_state: true, timeout_ms: 5_000]

      assert {:error, msg} = Fail.run(args, %{}, opts)
      assert msg =~ "fail"
      assert msg =~ "user_id"
    end

    test "does not include state when include_state is false" do
      args = %{prev_result: %{output: %{}, state: %{"secret" => "x"}}}
      opts = [message: ~s|"fail"|, include_state: false, timeout_ms: 5_000]

      assert {:error, "fail"} = Fail.run(args, %{}, opts)
    end

    test "has access to input and state bindings" do
      args = %{prev_result: %{output: %{"x" => 42}, state: %{"y" => 10}}}
      opts = [message: ~S|"x=#{input["x"]}, y=#{state["y"]}"|, timeout_ms: 5_000]

      assert {:error, msg} = Fail.run(args, %{}, opts)
      assert msg == "x=42, y=10"
    end

    test "returns error on expression evaluation failure" do
      args = %{prev_result: %{output: %{}, state: %{}}}
      opts = [message: "raise \"boom\"", timeout_ms: 5_000]

      assert {:error, msg} = Fail.run(args, %{}, opts)
      assert msg =~ "boom" or msg =~ "error"
    end

    test "returns error on timeout" do
      args = %{prev_result: %{output: %{}, state: %{}}}
      opts = [message: ~s|Process.sleep(10_000); "late"|, timeout_ms: 50]

      assert {:error, msg} = Fail.run(args, %{}, opts)
      assert msg =~ "timed out"
    end
  end
end
