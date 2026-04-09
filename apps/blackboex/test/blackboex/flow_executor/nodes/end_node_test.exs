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

  describe "run/3 with response_mapping" do
    @response_schema [
      %{"name" => "total", "type" => "integer", "required" => true, "constraints" => %{}},
      %{
        "name" => "items",
        "type" => "array",
        "required" => true,
        "constraints" => %{"item_type" => "string"}
      }
    ]

    @response_mapping [
      %{"response_field" => "total", "state_variable" => "counter"},
      %{"response_field" => "items", "state_variable" => "collected"}
    ]

    test "builds response from state mapping" do
      args = %{
        prev_result: %{
          output: "ignored",
          state: %{"counter" => 42, "collected" => ["a", "b"]}
        }
      }

      assert {:ok, %{output: response, state: _}} =
               EndNode.run(args, %{},
                 response_schema: @response_schema,
                 response_mapping: @response_mapping
               )

      assert response == %{"total" => 42, "items" => ["a", "b"]}
    end

    test "maps state variable to differently-named response field" do
      args = %{
        prev_result: %{
          output: "ignored",
          state: %{"internal_count" => 99}
        }
      }

      mapping = [%{"response_field" => "public_count", "state_variable" => "internal_count"}]

      schema = [
        %{"name" => "public_count", "type" => "integer", "required" => true, "constraints" => %{}}
      ]

      assert {:ok, %{output: %{"public_count" => 99}}} =
               EndNode.run(args, %{}, response_schema: schema, response_mapping: mapping)
    end

    test "maps multiple fields from state" do
      args = %{
        prev_result: %{
          output: "ignored",
          state: %{"a" => 1, "b" => "two", "c" => [3]}
        }
      }

      mapping = [
        %{"response_field" => "x", "state_variable" => "a"},
        %{"response_field" => "y", "state_variable" => "b"},
        %{"response_field" => "z", "state_variable" => "c"}
      ]

      schema = [
        %{"name" => "x", "type" => "integer", "constraints" => %{}},
        %{"name" => "y", "type" => "string", "constraints" => %{}},
        %{"name" => "z", "type" => "array", "constraints" => %{"item_type" => "integer"}}
      ]

      assert {:ok, %{output: response}} =
               EndNode.run(args, %{}, response_schema: schema, response_mapping: mapping)

      assert response == %{"x" => 1, "y" => "two", "z" => [3]}
    end

    test "returns error when mapped state variable missing" do
      args = %{prev_result: %{output: "x", state: %{}}}

      assert {:error, msg} =
               EndNode.run(args, %{},
                 response_schema: @response_schema,
                 response_mapping: @response_mapping
               )

      assert msg =~ "Response mapping failed"
      assert msg =~ "counter"
    end

    test "passes through last output when no mapping defined (backward compatible)" do
      args = %{prev_result: %{output: "pass_through", state: %{"a" => 1}}}
      assert {:ok, %{output: "pass_through"}} = EndNode.run(args, %{}, [])
    end

    test "passes through last output when mapping is empty list" do
      args = %{prev_result: %{output: "pass_through", state: %{}}}

      assert {:ok, %{output: "pass_through"}} =
               EndNode.run(args, %{}, response_schema: [], response_mapping: [])
    end

    test "handles branch-skipped marker unchanged regardless of mapping" do
      args = %{prev_result: %{output: :__branch_skipped__, state: %{}}}

      assert {:ok, %{output: :__branch_skipped__}} =
               EndNode.run(args, %{},
                 response_schema: @response_schema,
                 response_mapping: @response_mapping
               )
    end

    test "preserves nil, 0, false values through mapping" do
      args = %{
        prev_result: %{
          output: "ignored",
          state: %{"a" => nil, "b" => 0, "c" => false}
        }
      }

      mapping = [
        %{"response_field" => "x", "state_variable" => "a"},
        %{"response_field" => "y", "state_variable" => "b"},
        %{"response_field" => "z", "state_variable" => "c"}
      ]

      schema = [
        %{"name" => "x", "type" => "string", "constraints" => %{}},
        %{"name" => "y", "type" => "integer", "constraints" => %{}},
        %{"name" => "z", "type" => "boolean", "constraints" => %{}}
      ]

      assert {:ok, %{output: response}} =
               EndNode.run(args, %{}, response_schema: schema, response_mapping: mapping)

      assert response["x"] === nil
      assert response["y"] === 0
      assert response["z"] === false
    end
  end
end
