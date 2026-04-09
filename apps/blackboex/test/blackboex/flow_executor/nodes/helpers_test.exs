defmodule Blackboex.FlowExecutor.Nodes.HelpersTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.Helpers

  describe "extract_input_and_state/1" do
    test "extracts output and state from standard node result" do
      args = %{prev_result: %{output: "hello", state: %{"k" => 1}}}
      assert {"hello", %{"k" => 1}} = Helpers.extract_input_and_state(args)
    end

    test "extracts value and state from condition node result" do
      args = %{prev_result: %{value: 42, state: %{"k" => 2}}}
      assert {42, %{"k" => 2}} = Helpers.extract_input_and_state(args)
    end

    test "extracts value with empty state when state key absent" do
      args = %{prev_result: %{value: :some_atom}}
      assert {:some_atom, %{}} = Helpers.extract_input_and_state(args)
    end

    test "extracts input with empty state when no prev_result" do
      args = %{input: %{"name" => "test"}}
      assert {%{"name" => "test"}, %{}} = Helpers.extract_input_and_state(args)
    end
  end

  describe "execute_with_timeout/2" do
    test "returns ok result when function succeeds within timeout" do
      result = Helpers.execute_with_timeout(fn -> {:ok, 42} end, 1_000)
      assert {:ok, 42} = result
    end

    test "propagates error result from function" do
      result = Helpers.execute_with_timeout(fn -> {:error, "something went wrong"} end, 1_000)
      assert {:error, "something went wrong"} = result
    end

    test "returns timeout error when function exceeds deadline" do
      result =
        Helpers.execute_with_timeout(
          fn ->
            :timer.sleep(5_000)
            {:ok, :never}
          end,
          50
        )

      assert {:error, "execution timed out after 50ms"} = result
    end
  end

  describe "wrap_output/2" do
    test "builds standard output map" do
      assert %{output: "value", state: %{"x" => 1}} =
               Helpers.wrap_output("value", %{"x" => 1})
    end

    test "accepts empty state map" do
      assert %{output: nil, state: %{}} = Helpers.wrap_output(nil, %{})
    end
  end
end
