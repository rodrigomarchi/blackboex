defmodule Blackboex.FlowExecutor.Nodes.StartTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.Start

  describe "run/3" do
    test "passes payload through with initial state" do
      payload = %{"name" => "test", "value" => 42}
      assert {:ok, %{output: ^payload, state: %{}}} = Start.run(%{payload: payload}, %{}, [])
    end

    test "handles empty payload" do
      assert {:ok, %{output: %{}, state: %{}}} = Start.run(%{payload: %{}}, %{}, [])
    end

    test "handles list payload" do
      assert {:ok, %{output: [1, 2, 3], state: %{}}} = Start.run(%{payload: [1, 2, 3]}, %{}, [])
    end

    test "handles string payload" do
      assert {:ok, %{output: "hello", state: %{}}} = Start.run(%{payload: "hello"}, %{}, [])
    end
  end
end
