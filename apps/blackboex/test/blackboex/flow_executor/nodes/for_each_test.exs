defmodule Blackboex.FlowExecutor.Nodes.ForEachTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutor.Nodes.ForEach

  describe "run/3 — happy path" do
    test "doubles each number in a list" do
      args = %{prev_result: %{output: [1, 2, 3], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "item * 2"
      ]

      assert {:ok, %{output: [2, 4, 6], state: %{"results" => [2, 4, 6]}}} =
               ForEach.run(args, %{}, opts)
    end

    test "empty list returns empty results" do
      args = %{prev_result: %{output: [], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "item * 2"
      ]

      assert {:ok, %{output: [], state: %{"results" => []}}} =
               ForEach.run(args, %{}, opts)
    end

    test "preserves existing state keys and adds accumulator" do
      args = %{prev_result: %{output: [1, 2], state: %{"existing_key" => "preserved"}}}

      opts = [
        source_expression: "input",
        body_code: "item + 10"
      ]

      assert {:ok, %{output: [11, 12], state: state}} = ForEach.run(args, %{}, opts)
      assert state["existing_key"] == "preserved"
      assert state["results"] == [11, 12]
    end

    test "custom item variable name" do
      args = %{prev_result: %{output: ["a", "b"], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "String.upcase(el)",
        item_variable: "el"
      ]

      assert {:ok, %{output: ["A", "B"], state: %{"results" => ["A", "B"]}}} =
               ForEach.run(args, %{}, opts)
    end

    test "custom accumulator key stores results under that key" do
      args = %{prev_result: %{output: [1, 2, 3], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "item * item",
        accumulator: "squares"
      ]

      assert {:ok, %{output: [1, 4, 9], state: %{"squares" => [1, 4, 9]}}} =
               ForEach.run(args, %{}, opts)
    end

    test "source_expression extracts list from state" do
      args = %{prev_result: %{output: nil, state: %{"numbers" => [10, 20, 30]}}}

      opts = [
        source_expression: ~s|state["numbers"]|,
        body_code: "item + 1"
      ]

      assert {:ok, %{output: [11, 21, 31], state: state}} = ForEach.run(args, %{}, opts)
      assert state["results"] == [11, 21, 31]
    end

    test "body_code has access to index binding" do
      args = %{prev_result: %{output: ["a", "b", "c"], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "{item, index}"
      ]

      assert {:ok, %{output: [{"a", 0}, {"b", 1}, {"c", 2}], state: _}} =
               ForEach.run(args, %{}, opts)
    end
  end

  describe "run/3 — error cases" do
    test "error in item body returns error tuple" do
      args = %{prev_result: %{output: ["not_a_number"], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "String.to_integer(item)"
      ]

      assert {:error, reason} = ForEach.run(args, %{}, opts)
      assert reason =~ "item processing failed"
    end

    test "source_expression that raises returns error" do
      args = %{prev_result: %{output: nil, state: %{}}}

      opts = [
        source_expression: "String.to_integer(nil)",
        body_code: "item"
      ]

      assert {:error, reason} = ForEach.run(args, %{}, opts)
      assert reason =~ "source_expression evaluation failed"
    end

    test "source_expression returning non-list returns error" do
      args = %{prev_result: %{output: 42, state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "item"
      ]

      assert {:error, reason} = ForEach.run(args, %{}, opts)
      assert reason =~ "source_expression must return a list"
    end
  end

  describe "run/3 — timeout" do
    test "slow item triggers timeout error" do
      args = %{prev_result: %{output: [1], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: ":timer.sleep(5000); item",
        timeout_ms: 50
      ]

      assert {:error, reason} = ForEach.run(args, %{}, opts)
      assert reason =~ "timed out"
    end
  end

  describe "run/3 — batch_size option" do
    test "batch_size option is accepted and processing completes" do
      args = %{prev_result: %{output: [1, 2, 3, 4, 5], state: %{}}}

      opts = [
        source_expression: "input",
        body_code: "item * 3",
        batch_size: 2
      ]

      assert {:ok, %{output: [3, 6, 9, 12, 15], state: _}} = ForEach.run(args, %{}, opts)
    end
  end

  describe "run/3 — input argument shapes" do
    test "accepts input key shape (first node)" do
      args = %{input: [1, 2]}

      opts = [
        source_expression: "input",
        body_code: "item + 100"
      ]

      assert {:ok, %{output: [101, 102], state: _}} = ForEach.run(args, %{}, opts)
    end
  end
end
