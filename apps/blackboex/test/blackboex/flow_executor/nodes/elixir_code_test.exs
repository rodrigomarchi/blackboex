defmodule Blackboex.FlowExecutor.Nodes.ElixirCodeTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.ElixirCode

  describe "run/3" do
    test "evaluates code with input binding" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: "String.upcase(input)"]

      assert {:ok, %{output: "HELLO", state: %{}}} = ElixirCode.run(args, %{}, opts)
    end

    test "evaluates code with state binding" do
      args = %{prev_result: %{output: "world", state: %{"greeting" => "hello"}}}
      opts = [code: ~s|state["greeting"] <> " " <> input|]

      assert {:ok, %{output: "hello world", state: %{"greeting" => "hello"}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "handles {output, new_state} tuple return" do
      args = %{prev_result: %{output: 5, state: %{"count" => 10}}}
      opts = [code: ~s|{input * 2, Map.put(state, "count", state["count"] + input)}|]

      assert {:ok, %{output: 10, state: %{"count" => 15}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "plain value return keeps state unchanged" do
      args = %{prev_result: %{output: "data", state: %{"key" => "value"}}}
      opts = [code: "String.length(input)"]

      assert {:ok, %{output: 4, state: %{"key" => "value"}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "returns error on runtime exception" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: "String.to_integer(input)"]

      assert {:error, _reason} = ElixirCode.run(args, %{}, opts)
    end

    test "returns error on syntax error" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [code: "def foo do end end"]

      assert {:error, _reason} = ElixirCode.run(args, %{}, opts)
    end

    test "times out on long-running code" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [code: ":timer.sleep(5000); input", timeout_ms: 50]

      assert {:error, "execution timed out after" <> _} = ElixirCode.run(args, %{}, opts)
    end

    test "falls back to input key when prev_result not present" do
      args = %{input: "test"}
      opts = [code: "state"]

      assert {:ok, %{output: %{}, state: %{}}} = ElixirCode.run(args, %{}, opts)
    end
  end
end
