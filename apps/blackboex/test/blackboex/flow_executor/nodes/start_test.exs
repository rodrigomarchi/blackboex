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

  describe "run/3 with payload_schema" do
    @payload_schema [
      %{
        "name" => "name",
        "type" => "string",
        "required" => true,
        "constraints" => %{"min_length" => 1}
      },
      %{"name" => "age", "type" => "integer", "required" => false, "constraints" => %{"min" => 0}}
    ]

    test "validates payload and passes through when valid" do
      payload = %{"name" => "Ana", "age" => 30}

      assert {:ok, %{output: ^payload, state: %{}}} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)
    end

    test "returns error when required payload field is missing" do
      payload = %{"age" => 30}

      assert {:error, msg} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)

      assert msg =~ "name"
      assert msg =~ "required"
    end

    test "returns error when payload field has wrong type" do
      payload = %{"name" => 42}

      assert {:error, msg} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)

      assert msg =~ "name"
      assert msg =~ "string"
    end

    test "returns error when string constraint violated (min_length)" do
      payload = %{"name" => ""}

      assert {:error, msg} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)

      assert msg =~ "name"
    end

    test "returns error when integer constraint violated (min)" do
      payload = %{"name" => "Ana", "age" => -1}

      assert {:error, msg} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)

      assert msg =~ "age"
    end

    test "returns descriptive error messages with field paths" do
      payload = %{}

      assert {:error, msg} =
               Start.run(%{payload: payload}, %{}, payload_schema: @payload_schema)

      assert msg =~ "Payload validation failed"
      assert msg =~ "name"
    end

    test "skips validation when payload_schema is nil (backward compatible)" do
      payload = %{"anything" => "goes"}

      assert {:ok, %{output: ^payload, state: %{}}} =
               Start.run(%{payload: payload}, %{}, payload_schema: nil)
    end

    test "skips validation when payload_schema is empty list" do
      payload = %{"anything" => "goes"}

      assert {:ok, %{output: ^payload, state: %{}}} =
               Start.run(%{payload: payload}, %{}, payload_schema: [])
    end
  end

  describe "run/3 with state_schema" do
    @state_schema [
      %{"name" => "counter", "type" => "integer", "initial_value" => 0},
      %{"name" => "label", "type" => "string", "initial_value" => "start"},
      %{"name" => "items", "type" => "array", "initial_value" => []},
      %{"name" => "config", "type" => "object", "initial_value" => %{"debug" => false}}
    ]

    test "initializes state from state_schema initial values" do
      payload = %{"x" => 1}

      assert {:ok, %{output: ^payload, state: state}} =
               Start.run(%{payload: payload}, %{}, state_schema: @state_schema)

      assert state["counter"] == 0
      assert state["label"] == "start"
      assert state["items"] == []
      assert state["config"] == %{"debug" => false}
    end

    test "initializes state with mixed types" do
      assert {:ok, %{state: state}} =
               Start.run(%{payload: %{}}, %{}, state_schema: @state_schema)

      assert is_integer(state["counter"])
      assert is_binary(state["label"])
      assert is_list(state["items"])
      assert is_map(state["config"])
    end

    test "initializes empty state when state_schema is nil (backward compatible)" do
      assert {:ok, %{state: %{}}} = Start.run(%{payload: %{}}, %{}, state_schema: nil)
    end

    test "initializes empty state when state_schema is empty list" do
      assert {:ok, %{state: %{}}} = Start.run(%{payload: %{}}, %{}, state_schema: [])
    end

    test "handles 0 and false as valid initial values (not nil)" do
      schema = [
        %{"name" => "count", "type" => "integer", "initial_value" => 0},
        %{"name" => "flag", "type" => "boolean", "initial_value" => false}
      ]

      assert {:ok, %{state: state}} = Start.run(%{payload: %{}}, %{}, state_schema: schema)
      assert state["count"] === 0
      assert state["flag"] === false
    end
  end

  describe "run/3 with both schemas" do
    test "validates payload AND initializes state in single execution" do
      payload_schema = [
        %{"name" => "name", "type" => "string", "required" => true, "constraints" => %{}}
      ]

      state_schema = [
        %{"name" => "greeting", "type" => "string", "initial_value" => ""}
      ]

      payload = %{"name" => "Ana"}

      assert {:ok, %{output: ^payload, state: state}} =
               Start.run(%{payload: payload}, %{},
                 payload_schema: payload_schema,
                 state_schema: state_schema
               )

      assert state["greeting"] == ""
    end

    test "returns payload validation error before initializing state" do
      payload_schema = [
        %{"name" => "name", "type" => "string", "required" => true, "constraints" => %{}}
      ]

      state_schema = [
        %{"name" => "greeting", "type" => "string", "initial_value" => ""}
      ]

      assert {:error, msg} =
               Start.run(%{payload: %{}}, %{},
                 payload_schema: payload_schema,
                 state_schema: state_schema
               )

      assert msg =~ "Payload validation failed"
    end
  end
end
