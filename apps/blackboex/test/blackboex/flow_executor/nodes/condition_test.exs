defmodule Blackboex.FlowExecutor.Nodes.ConditionTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.Condition

  describe "run/3" do
    test "returns branch index 0 for true condition" do
      args = %{prev_result: %{output: %{"status" => "ok"}, state: %{}}}
      opts = [expression: ~s|if input["status"] == "ok", do: 0, else: 1|]

      assert {:ok, %{branch: 0, value: %{"status" => "ok"}, state: %{}}} =
               Condition.run(args, %{}, opts)
    end

    test "returns branch index 1 for false condition" do
      args = %{prev_result: %{output: %{"status" => "error"}, state: %{}}}
      opts = [expression: ~s|if input["status"] == "ok", do: 0, else: 1|]

      assert {:ok, %{branch: 1, value: %{"status" => "error"}, state: %{}}} =
               Condition.run(args, %{}, opts)
    end

    test "supports multi-branch with cond" do
      args = %{prev_result: %{output: %{"level" => 3}, state: %{}}}

      expression = """
      cond do
        input["level"] > 5 -> 0
        input["level"] > 2 -> 1
        true -> 2
      end
      """

      opts = [expression: expression]

      assert {:ok, %{branch: 1}} = Condition.run(args, %{}, opts)
    end

    test "can access state" do
      args = %{prev_result: %{output: "data", state: %{"mode" => "fast"}}}
      opts = [expression: ~s|if state["mode"] == "fast", do: 0, else: 1|]

      assert {:ok, %{branch: 0}} = Condition.run(args, %{}, opts)
    end

    test "returns error for non-integer result" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [expression: ~s["not_an_integer"]]

      assert {:error, "condition expression must return a non-negative integer" <> _} =
               Condition.run(args, %{}, opts)
    end

    test "returns error for negative integer" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [expression: "-1"]

      assert {:error, "condition expression must return a non-negative integer" <> _} =
               Condition.run(args, %{}, opts)
    end

    test "returns error on exception" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [expression: "String.to_integer(input)"]

      assert {:error, _reason} = Condition.run(args, %{}, opts)
    end

    test "propagates :__branch_skipped__ without evaluating the expression" do
      # A condition node downstream of another condition's non-taken branch
      # receives :__branch_skipped__ as input. It must not evaluate the
      # expression (which would crash on `input["key"]`) — instead it should
      # return a sentinel branch that no source_port can match, so every
      # downstream edge propagates the skip.
      args = %{prev_result: %{output: :__branch_skipped__, state: %{"keep" => "me"}}}
      opts = [expression: ~s|if input["decision"] == "approved", do: 0, else: 1|]

      assert {:ok,
              %{
                branch: :__branch_skipped__,
                value: :__branch_skipped__,
                state: %{"keep" => "me"}
              }} = Condition.run(args, %{}, opts)
    end
  end
end
