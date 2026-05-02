defmodule Blackboex.Flows.SampleInputTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.SchemaValidator
  alias Blackboex.Flows.SampleInput
  alias Blackboex.Samples.FlowTemplates.AllNodesDemo
  alias Blackboex.Samples.FlowTemplates.HelloWorld

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp build_flow(payload_schema) do
    %Blackboex.Flows.Flow{
      definition: %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{"name" => "Start", "payload_schema" => payload_schema}
          }
        ],
        "edges" => []
      }
    }
  end

  defp string_field(name, opts \\ %{}) do
    Map.merge(
      %{"name" => name, "type" => "string", "required" => false, "constraints" => %{}},
      opts
    )
  end

  defp integer_field(name, opts \\ %{}) do
    Map.merge(
      %{"name" => name, "type" => "integer", "required" => false, "constraints" => %{}},
      opts
    )
  end

  defp float_field(name, opts \\ %{}) do
    Map.merge(
      %{"name" => name, "type" => "float", "required" => false, "constraints" => %{}},
      opts
    )
  end

  defp boolean_field(name) do
    %{"name" => name, "type" => "boolean", "required" => false, "constraints" => %{}}
  end

  defp array_field(name, constraints \\ %{}) do
    %{"name" => name, "type" => "array", "required" => false, "constraints" => constraints}
  end

  defp object_field(name, opts \\ %{}) do
    Map.merge(
      %{"name" => name, "type" => "object", "required" => false, "constraints" => %{}},
      opts
    )
  end

  # ── Boundary cases ──────────────────────────────────────────────────────

  describe "generate/1 — boundary cases" do
    test "returns empty map when flow has empty definition" do
      flow = %Blackboex.Flows.Flow{definition: %{}}
      assert SampleInput.generate(flow) == %{}
    end

    test "returns empty map when flow has nil definition" do
      flow = %Blackboex.Flows.Flow{definition: nil}
      assert SampleInput.generate(flow) == %{}
    end

    test "returns empty map when definition has no nodes" do
      flow = %Blackboex.Flows.Flow{definition: %{"nodes" => []}}
      assert SampleInput.generate(flow) == %{}
    end

    test "returns empty map when start node has no payload_schema" do
      flow = %Blackboex.Flows.Flow{
        definition: %{
          "nodes" => [
            %{"id" => "n1", "type" => "start", "data" => %{"name" => "Start"}}
          ]
        }
      }

      assert SampleInput.generate(flow) == %{}
    end

    test "returns empty map when payload_schema is empty list" do
      flow = build_flow([])
      assert SampleInput.generate(flow) == %{}
    end

    test "returns empty map when payload_schema is nil" do
      flow = build_flow(nil)
      assert SampleInput.generate(flow) == %{}
    end
  end

  # ── Basic types ─────────────────────────────────────────────────────────

  describe "generate/1 — basic types" do
    test "generates example string" do
      flow = build_flow([string_field("greeting")])
      assert SampleInput.generate(flow) == %{"greeting" => "example"}
    end

    test "generates example integer" do
      flow = build_flow([integer_field("age")])
      assert SampleInput.generate(flow) == %{"age" => 42}
    end

    test "generates example float" do
      flow = build_flow([float_field("score")])
      assert SampleInput.generate(flow) == %{"score" => 3.14}
    end

    test "generates example boolean" do
      flow = build_flow([boolean_field("active")])
      assert SampleInput.generate(flow) == %{"active" => true}
    end

    test "generates example empty array when no constraints" do
      flow = build_flow([array_field("tags")])
      assert SampleInput.generate(flow) == %{"tags" => []}
    end

    test "generates example empty object when no nested fields" do
      flow = build_flow([object_field("meta")])
      assert SampleInput.generate(flow) == %{"meta" => %{}}
    end

    test "generates nil for unknown type" do
      flow = build_flow([%{"name" => "x", "type" => "foobar", "constraints" => %{}}])
      assert SampleInput.generate(flow) == %{"x" => nil}
    end
  end

  # ── Multiple fields ─────────────────────────────────────────────────────

  describe "generate/1 — multiple fields" do
    test "generates all fields for multi-field schema" do
      flow = build_flow([string_field("name"), integer_field("age"), boolean_field("active")])
      result = SampleInput.generate(flow)

      assert result == %{"name" => "example", "age" => 42, "active" => true}
    end

    test "handles hello_world template schema" do
      flow =
        build_flow([
          string_field("name", %{"required" => true, "constraints" => %{"min_length" => 1}}),
          string_field("email"),
          string_field("phone")
        ])

      result = SampleInput.generate(flow)

      assert result["name"] == "a"
      assert result["email"] == "example"
      assert result["phone"] == "example"
    end

    test "handles all_nodes_demo template schema" do
      flow =
        build_flow([
          string_field("name", %{"required" => true, "constraints" => %{"min_length" => 1}}),
          string_field("email"),
          array_field("items", %{"item_type" => "string"}),
          boolean_field("needs_approval")
        ])

      result = SampleInput.generate(flow)

      assert is_binary(result["name"])
      assert is_binary(result["email"])
      assert is_list(result["items"])
      assert is_boolean(result["needs_approval"])
    end
  end

  # ── String constraints ──────────────────────────────────────────────────

  describe "generate/1 — string constraints" do
    test "uses first enum value when enum constraint present" do
      flow =
        build_flow([
          string_field("priority", %{"constraints" => %{"enum" => ["low", "medium", "high"]}})
        ])

      assert SampleInput.generate(flow)["priority"] == "low"
    end

    test "generates string of min_length when min_length constraint" do
      flow =
        build_flow([
          string_field("code", %{"constraints" => %{"min_length" => 3}})
        ])

      result = SampleInput.generate(flow)["code"]
      assert String.length(result) == 3
    end

    test "generates string within max_length when max_length only" do
      flow =
        build_flow([
          string_field("short", %{"constraints" => %{"max_length" => 5}})
        ])

      result = SampleInput.generate(flow)["short"]
      assert String.length(result) <= 5
    end

    test "generates string respecting both min and max_length" do
      flow =
        build_flow([
          string_field("mid", %{"constraints" => %{"min_length" => 2, "max_length" => 5}})
        ])

      result = SampleInput.generate(flow)["mid"]
      assert String.length(result) >= 2
      assert String.length(result) <= 5
    end

    test "enum takes priority over min_length" do
      flow =
        build_flow([
          string_field("choice", %{
            "constraints" => %{"enum" => ["yes", "no"], "min_length" => 10}
          })
        ])

      assert SampleInput.generate(flow)["choice"] == "yes"
    end

    test "generates string with empty constraints map" do
      flow = build_flow([string_field("plain", %{"constraints" => %{}})])
      assert SampleInput.generate(flow)["plain"] == "example"
    end
  end

  # ── Number constraints ──────────────────────────────────────────────────

  describe "generate/1 — number constraints" do
    test "uses min value for integer when min constraint" do
      flow =
        build_flow([integer_field("count", %{"constraints" => %{"min" => 10}})])

      assert SampleInput.generate(flow)["count"] == 10
    end

    test "uses min value for float when min constraint" do
      flow =
        build_flow([float_field("rate", %{"constraints" => %{"min" => 1.5}})])

      assert SampleInput.generate(flow)["rate"] == 1.5
    end

    test "uses default when only max constraint and default is within range" do
      flow =
        build_flow([integer_field("big", %{"constraints" => %{"max" => 100}})])

      assert SampleInput.generate(flow)["big"] == 42
    end

    test "clamps default to max when default exceeds max" do
      flow =
        build_flow([integer_field("small", %{"constraints" => %{"max" => 10}})])

      assert SampleInput.generate(flow)["small"] == 10
    end

    test "uses min when both min and max" do
      flow =
        build_flow([integer_field("range", %{"constraints" => %{"min" => 5, "max" => 10}})])

      assert SampleInput.generate(flow)["range"] == 5
    end
  end

  # ── Array constraints ───────────────────────────────────────────────────

  describe "generate/1 — array constraints" do
    test "generates array with one string item when item_type is string" do
      flow = build_flow([array_field("tags", %{"item_type" => "string"})])
      assert SampleInput.generate(flow)["tags"] == ["example"]
    end

    test "generates array with one integer item when item_type is integer" do
      flow = build_flow([array_field("ids", %{"item_type" => "integer"})])
      assert SampleInput.generate(flow)["ids"] == [42]
    end

    test "generates array with one boolean item when item_type is boolean" do
      flow = build_flow([array_field("flags", %{"item_type" => "boolean"})])
      assert SampleInput.generate(flow)["flags"] == [true]
    end

    test "generates array with one object item when item_type is object + item_fields" do
      flow =
        build_flow([
          array_field("users", %{
            "item_type" => "object",
            "item_fields" => [string_field("name"), integer_field("age")]
          })
        ])

      result = SampleInput.generate(flow)["users"]
      assert result == [%{"name" => "example", "age" => 42}]
    end

    test "generates empty array when no item_type constraint" do
      flow = build_flow([array_field("misc", %{})])
      assert SampleInput.generate(flow)["misc"] == []
    end

    test "respects min_items by generating that many items" do
      flow =
        build_flow([
          array_field("items", %{"item_type" => "string", "min_items" => 2})
        ])

      result = SampleInput.generate(flow)["items"]
      assert length(result) == 2
      assert Enum.all?(result, &is_binary/1)
    end
  end

  # ── Nested objects ──────────────────────────────────────────────────────

  describe "generate/1 — nested objects" do
    test "generates nested object from fields" do
      flow =
        build_flow([
          object_field("address", %{
            "fields" => [string_field("city"), integer_field("zip")]
          })
        ])

      assert SampleInput.generate(flow)["address"] == %{"city" => "example", "zip" => 42}
    end

    test "generates deeply nested objects (2 levels)" do
      flow =
        build_flow([
          object_field("outer", %{
            "fields" => [
              object_field("inner", %{
                "fields" => [string_field("value")]
              })
            ]
          })
        ])

      assert SampleInput.generate(flow) == %{
               "outer" => %{"inner" => %{"value" => "example"}}
             }
    end

    test "handles object with no fields key" do
      flow = build_flow([object_field("empty")])
      assert SampleInput.generate(flow)["empty"] == %{}
    end
  end

  # ── Missing/malformed field keys ────────────────────────────────────────

  describe "generate/1 — missing/malformed field keys" do
    test "handles field without constraints key" do
      flow = build_flow([%{"name" => "x", "type" => "string"}])
      assert SampleInput.generate(flow)["x"] == "example"
    end

    test "handles field without type key" do
      flow = build_flow([%{"name" => "x"}])
      assert SampleInput.generate(flow)["x"] == nil
    end

    test "handles field without name key — skipped without crash" do
      flow = build_flow([%{"type" => "string"}, string_field("ok")])
      result = SampleInput.generate(flow)

      assert result["ok"] == "example"
      # No crash, and nil-keyed entry is acceptable
    end
  end

  # ── Real-world integration ──────────────────────────────────────────────

  describe "generate/1 — real-world integration" do
    test "generates valid input that passes SchemaValidator for hello_world" do
      template = HelloWorld.template()
      start = Enum.find(template.definition["nodes"], &(&1["type"] == "start"))
      schema = start["data"]["payload_schema"]

      flow = build_flow(schema)
      example = SampleInput.generate(flow)

      assert {:ok, _} = SchemaValidator.validate_payload(example, schema)
    end

    test "generates valid input that passes SchemaValidator for all_nodes_demo" do
      template = AllNodesDemo.template()
      start = Enum.find(template.definition["nodes"], &(&1["type"] == "start"))
      schema = start["data"]["payload_schema"]

      flow = build_flow(schema)
      example = SampleInput.generate(flow)

      assert {:ok, _} = SchemaValidator.validate_payload(example, schema)
    end
  end
end
