defmodule Blackboex.FlowExecutor.Nodes.EndNodeTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.EndNode

  describe "run/3" do
    test "returns output and state from prev_result" do
      args = %{prev_result: %{output: "final_result", state: %{"accumulated" => true}}}

      assert {:ok, %{output: "final_result", state: %{"accumulated" => true}}} =
               EndNode.run(args, %{}, [])
    end

    test "handles empty state" do
      args = %{prev_result: %{output: %{"data" => [1, 2, 3]}, state: %{}}}

      assert {:ok, %{output: %{"data" => [1, 2, 3]}, state: %{}}} =
               EndNode.run(args, %{}, [])
    end

    test "falls back to input key" do
      assert {:ok, %{output: nil, state: %{}}} = EndNode.run(%{input: nil}, %{}, [])
    end
  end
end
