defmodule Blackboex.FlowExecutor.SchemaValidatorTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.SchemaValidator

  # ── Helper builders ──

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

  defp boolean_field(name, opts \\ %{}) do
    Map.merge(
      %{"name" => name, "type" => "boolean", "required" => false, "constraints" => %{}},
      opts
    )
  end

  defp array_field(name, item_type, opts \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "type" => "array",
        "required" => false,
        "constraints" => %{"item_type" => item_type}
      },
      opts
    )
  end

  defp object_field(name, fields, opts \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "type" => "object",
        "required" => false,
        "constraints" => %{},
        "fields" => fields
      },
      opts
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # validate_schema_definition/1
  # ═══════════════════════════════════════════════════════════════════════════

  describe "validate_schema_definition/1 — happy paths" do
    test "accepts empty schema (no fields)" do
      assert :ok = SchemaValidator.validate_schema_definition([])
    end

    test "accepts single string field with no constraints" do
      assert :ok = SchemaValidator.validate_schema_definition([string_field("name")])
    end

    test "accepts all primitive types" do
      schema = [
        string_field("a"),
        integer_field("b"),
        float_field("c"),
        boolean_field("d")
      ]

      assert :ok = SchemaValidator.validate_schema_definition(schema)
    end

    test "accepts array field with item_type" do
      assert :ok = SchemaValidator.validate_schema_definition([array_field("tags", "string")])
    end

    test "accepts object field with nested fields" do
      schema = [object_field("meta", [string_field("source")])]
      assert :ok = SchemaValidator.validate_schema_definition(schema)
    end

    test "accepts field with all valid string constraints" do
      field =
        string_field("code", %{
          "constraints" => %{
            "min_length" => 1,
            "max_length" => 10,
            "pattern" => "^[A-Z]+$",
            "enum" => ["A", "B", "C"]
          }
        })

      assert :ok = SchemaValidator.validate_schema_definition([field])
    end

    test "accepts field with all valid integer constraints" do
      field = integer_field("age", %{"constraints" => %{"min" => 0, "max" => 150}})
      assert :ok = SchemaValidator.validate_schema_definition([field])
    end

    test "accepts field with all valid float constraints" do
      field = float_field("price", %{"constraints" => %{"min" => 0.0, "max" => 9_999.99}})
      assert :ok = SchemaValidator.validate_schema_definition([field])
    end

    test "accepts field with all valid array constraints" do
      field =
        array_field("items", "string", %{
          "constraints" => %{"item_type" => "string", "min_items" => 1, "max_items" => 100}
        })

      assert :ok = SchemaValidator.validate_schema_definition([field])
    end

    test "accepts 2-level nested object" do
      schema = [
        object_field("level1", [
          object_field("level2", [string_field("value")])
        ])
      ]

      assert :ok = SchemaValidator.validate_schema_definition(schema)
    end

    test "accepts 3-level nested object (max depth)" do
      schema = [
        object_field("l1", [
          object_field("l2", [
            object_field("l3", [string_field("deep")])
          ])
        ])
      ]

      assert :ok = SchemaValidator.validate_schema_definition(schema)
    end

    test "accepts array of objects with nested fields via item_fields" do
      field = %{
        "name" => "users",
        "type" => "array",
        "required" => false,
        "constraints" => %{
          "item_type" => "object",
          "item_fields" => [string_field("name"), integer_field("age")]
        }
      }

      assert :ok = SchemaValidator.validate_schema_definition([field])
    end
  end

  describe "validate_schema_definition/1 — error paths" do
    test "rejects unknown type" do
      field = %{"name" => "d", "type" => "date", "required" => false, "constraints" => %{}}
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "date"))
    end

    test "rejects field without name" do
      field = %{"type" => "string", "required" => false, "constraints" => %{}}
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects field without type" do
      field = %{"name" => "x", "required" => false, "constraints" => %{}}
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects field with empty string name" do
      field = string_field("", %{})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "name"))
    end

    test "rejects field with name containing spaces" do
      field = string_field("my field", %{})
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects field with name containing special characters" do
      field = string_field("my-field!", %{})
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects duplicate field names at same level" do
      schema = [string_field("name"), integer_field("name")]
      assert {:error, errors} = SchemaValidator.validate_schema_definition(schema)
      assert Enum.any?(errors, &String.contains?(&1, "duplicate"))
    end

    test "allows same field name at different nesting levels" do
      schema = [
        string_field("name"),
        object_field("meta", [string_field("name")])
      ]

      assert :ok = SchemaValidator.validate_schema_definition(schema)
    end

    test "rejects 4-level nested object (exceeds max depth)" do
      schema = [
        object_field("l1", [
          object_field("l2", [
            object_field("l3", [
              object_field("l4", [string_field("too_deep")])
            ])
          ])
        ])
      ]

      assert {:error, errors} = SchemaValidator.validate_schema_definition(schema)
      assert Enum.any?(errors, &String.contains?(&1, "depth"))
    end

    test "rejects string constraint on integer field" do
      field = integer_field("age", %{"constraints" => %{"min_length" => 1}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min_length"))
    end

    test "rejects integer constraint on string field" do
      field = string_field("name", %{"constraints" => %{"min" => 0}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min"))
    end

    test "rejects array constraint on non-array field" do
      field = string_field("name", %{"constraints" => %{"min_items" => 1}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min_items"))
    end

    test "rejects array field without item_type" do
      field = %{
        "name" => "items",
        "type" => "array",
        "required" => false,
        "constraints" => %{}
      }

      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "item_type"))
    end

    test "rejects unknown constraint key" do
      field = string_field("x", %{"constraints" => %{"foo" => "bar"}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "foo"))
    end

    test "rejects min_length > max_length" do
      field = string_field("x", %{"constraints" => %{"min_length" => 10, "max_length" => 5}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min_length"))
    end

    test "rejects min > max for integer" do
      field = integer_field("x", %{"constraints" => %{"min" => 100, "max" => 50}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min"))
    end

    test "rejects min > max for float" do
      field = float_field("x", %{"constraints" => %{"min" => 10.0, "max" => 5.0}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min"))
    end

    test "rejects min_items > max_items" do
      field =
        array_field("x", "string", %{
          "constraints" => %{"item_type" => "string", "min_items" => 10, "max_items" => 5}
        })

      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "min_items"))
    end

    test "rejects negative min_length" do
      field = string_field("x", %{"constraints" => %{"min_length" => -1}})
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects negative min_items" do
      field =
        array_field("x", "string", %{
          "constraints" => %{"item_type" => "string", "min_items" => -1}
        })

      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects enum with empty list" do
      field = string_field("x", %{"constraints" => %{"enum" => []}})
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects enum with non-string values" do
      field = string_field("x", %{"constraints" => %{"enum" => [1, 2, 3]}})
      assert {:error, _} = SchemaValidator.validate_schema_definition([field])
    end

    test "rejects pattern with invalid regex" do
      field = string_field("x", %{"constraints" => %{"pattern" => "[invalid("}})
      assert {:error, errors} = SchemaValidator.validate_schema_definition([field])
      assert Enum.any?(errors, &String.contains?(&1, "pattern"))
    end

    test "rejects non-list input" do
      assert {:error, _} = SchemaValidator.validate_schema_definition(%{"bad" => true})
      assert {:error, _} = SchemaValidator.validate_schema_definition("bad")
      assert {:error, _} = SchemaValidator.validate_schema_definition(nil)
    end

    test "rejects field with non-map entry in list" do
      assert {:error, _} = SchemaValidator.validate_schema_definition(["not_a_map"])
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # validate_payload/2
  # ═══════════════════════════════════════════════════════════════════════════

  describe "validate_payload/2 — happy paths" do
    test "accepts valid payload matching all field types" do
      schema = [
        string_field("name", %{"required" => true}),
        integer_field("age", %{"required" => true}),
        float_field("score", %{"required" => true}),
        boolean_field("active", %{"required" => true})
      ]

      payload = %{"name" => "Ana", "age" => 30, "score" => 9.5, "active" => true}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts payload with optional fields missing" do
      schema = [
        string_field("name", %{"required" => true}),
        string_field("email", %{"required" => false})
      ]

      payload = %{"name" => "Ana"}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts payload with extra fields not in schema" do
      schema = [string_field("name", %{"required" => true})]
      payload = %{"name" => "Ana", "extra" => "ignored"}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts empty payload when all fields are optional" do
      schema = [string_field("name"), integer_field("age")]
      assert {:ok, %{}} = SchemaValidator.validate_payload(%{}, schema)
    end

    test "accepts payload with nil value for optional field" do
      schema = [string_field("name")]
      payload = %{"name" => nil}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts nested object matching nested schema" do
      schema = [
        object_field(
          "address",
          [
            string_field("city", %{"required" => true}),
            string_field("zip")
          ],
          %{"required" => true}
        )
      ]

      payload = %{"address" => %{"city" => "SP"}}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts array of strings matching array(string) schema" do
      schema = [array_field("tags", "string", %{"required" => true})]
      payload = %{"tags" => ["a", "b", "c"]}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts array of objects matching array(object) schema" do
      schema = [
        %{
          "name" => "users",
          "type" => "array",
          "required" => true,
          "constraints" => %{
            "item_type" => "object",
            "item_fields" => [
              string_field("name", %{"required" => true}),
              integer_field("age")
            ]
          }
        }
      ]

      payload = %{"users" => [%{"name" => "Ana", "age" => 30}, %{"name" => "Bob"}]}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "accepts empty array when min_items not set" do
      schema = [array_field("tags", "string")]
      payload = %{"tags" => []}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end
  end

  describe "validate_payload/2 — type validation" do
    test "rejects string field receiving integer" do
      schema = [string_field("name", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"name" => 42}, schema)
      assert Enum.any?(errors, &(&1.field == "name"))
    end

    test "rejects integer field receiving string" do
      schema = [integer_field("age", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"age" => "thirty"}, schema)
      assert Enum.any?(errors, &(&1.field == "age"))
    end

    test "rejects integer field receiving float" do
      schema = [integer_field("count", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"count" => 1.5}, schema)
      assert Enum.any?(errors, &(&1.field == "count"))
    end

    test "rejects float field receiving string" do
      schema = [float_field("price", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"price" => "cheap"}, schema)
      assert Enum.any?(errors, &(&1.field == "price"))
    end

    test "rejects boolean field receiving string 'true'" do
      schema = [boolean_field("active", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"active" => "true"}, schema)
      assert Enum.any?(errors, &(&1.field == "active"))
    end

    test "rejects boolean field receiving 1 or 0" do
      schema = [boolean_field("active", %{"required" => true})]
      assert {:error, _} = SchemaValidator.validate_payload(%{"active" => 1}, schema)
      assert {:error, _} = SchemaValidator.validate_payload(%{"active" => 0}, schema)
    end

    test "rejects array field receiving non-list value" do
      schema = [array_field("tags", "string", %{"required" => true})]

      assert {:error, errors} =
               SchemaValidator.validate_payload(%{"tags" => "not_a_list"}, schema)

      assert Enum.any?(errors, &(&1.field == "tags"))
    end

    test "rejects object field receiving non-map value" do
      schema = [object_field("meta", [string_field("x")], %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"meta" => "not_a_map"}, schema)
      assert Enum.any?(errors, &(&1.field == "meta"))
    end
  end

  describe "validate_payload/2 — required validation" do
    test "rejects missing required field" do
      schema = [string_field("name", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{}, schema)
      assert Enum.any?(errors, &(&1.field == "name" and String.contains?(&1.message, "required")))
    end

    test "rejects nil value for required field" do
      schema = [string_field("name", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"name" => nil}, schema)
      assert Enum.any?(errors, &(&1.field == "name"))
    end

    test "rejects empty string for required string field" do
      schema = [string_field("name", %{"required" => true})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"name" => ""}, schema)
      assert Enum.any?(errors, &(&1.field == "name"))
    end
  end

  describe "validate_payload/2 — string constraints" do
    test "rejects string shorter than min_length" do
      schema = [
        string_field("code", %{"required" => true, "constraints" => %{"min_length" => 3}})
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"code" => "ab"}, schema)
      assert Enum.any?(errors, &(&1.field == "code"))
    end

    test "rejects string longer than max_length" do
      schema = [
        string_field("code", %{"required" => true, "constraints" => %{"max_length" => 3}})
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"code" => "abcd"}, schema)
      assert Enum.any?(errors, &(&1.field == "code"))
    end

    test "rejects string not matching pattern regex" do
      schema = [
        string_field("code", %{"required" => true, "constraints" => %{"pattern" => "^[A-Z]+$"}})
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"code" => "abc"}, schema)
      assert Enum.any?(errors, &(&1.field == "code"))
    end

    test "accepts string matching pattern regex" do
      schema = [
        string_field("code", %{"required" => true, "constraints" => %{"pattern" => "^[A-Z]+$"}})
      ]

      assert {:ok, _} = SchemaValidator.validate_payload(%{"code" => "ABC"}, schema)
    end

    test "rejects catastrophic backtracking regex pattern with timeout" do
      # Classic ReDoS pattern: (a+)+ against a string of 'a's followed by non-match
      schema = [
        string_field("data", %{
          "required" => true,
          "constraints" => %{"pattern" => "^(a+)+$"}
        })
      ]

      evil_input = String.duplicate("a", 30) <> "!"

      assert {:error, errors} = SchemaValidator.validate_payload(%{"data" => evil_input}, schema)
      assert Enum.any?(errors, &(&1.field == "data"))
    end

    test "rejects string not in enum list" do
      schema = [
        string_field("status", %{
          "required" => true,
          "constraints" => %{"enum" => ["active", "inactive"]}
        })
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"status" => "deleted"}, schema)
      assert Enum.any?(errors, &(&1.field == "status"))
    end

    test "accepts string in enum list" do
      schema = [
        string_field("status", %{
          "required" => true,
          "constraints" => %{"enum" => ["active", "inactive"]}
        })
      ]

      assert {:ok, _} = SchemaValidator.validate_payload(%{"status" => "active"}, schema)
    end
  end

  describe "validate_payload/2 — number constraints" do
    test "rejects integer below min" do
      schema = [integer_field("age", %{"required" => true, "constraints" => %{"min" => 18}})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"age" => 10}, schema)
      assert Enum.any?(errors, &(&1.field == "age"))
    end

    test "rejects integer above max" do
      schema = [integer_field("age", %{"required" => true, "constraints" => %{"max" => 100}})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"age" => 150}, schema)
      assert Enum.any?(errors, &(&1.field == "age"))
    end

    test "accepts integer at exact min boundary" do
      schema = [integer_field("age", %{"required" => true, "constraints" => %{"min" => 18}})]
      assert {:ok, _} = SchemaValidator.validate_payload(%{"age" => 18}, schema)
    end

    test "accepts integer at exact max boundary" do
      schema = [integer_field("age", %{"required" => true, "constraints" => %{"max" => 100}})]
      assert {:ok, _} = SchemaValidator.validate_payload(%{"age" => 100}, schema)
    end

    test "rejects float below min" do
      schema = [float_field("price", %{"required" => true, "constraints" => %{"min" => 0.0}})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"price" => -0.01}, schema)
      assert Enum.any?(errors, &(&1.field == "price"))
    end

    test "rejects float above max" do
      schema = [float_field("price", %{"required" => true, "constraints" => %{"max" => 999.99}})]
      assert {:error, errors} = SchemaValidator.validate_payload(%{"price" => 1000.0}, schema)
      assert Enum.any?(errors, &(&1.field == "price"))
    end
  end

  describe "validate_payload/2 — array constraints" do
    test "rejects array with fewer items than min_items" do
      schema = [
        array_field("tags", "string", %{
          "required" => true,
          "constraints" => %{"item_type" => "string", "min_items" => 2}
        })
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"tags" => ["one"]}, schema)
      assert Enum.any?(errors, &(&1.field == "tags"))
    end

    test "rejects array with more items than max_items" do
      schema = [
        array_field("tags", "string", %{
          "required" => true,
          "constraints" => %{"item_type" => "string", "max_items" => 2}
        })
      ]

      assert {:error, errors} =
               SchemaValidator.validate_payload(%{"tags" => ["a", "b", "c"]}, schema)

      assert Enum.any?(errors, &(&1.field == "tags"))
    end

    test "rejects array with wrong item types" do
      schema = [
        array_field("tags", "string", %{
          "required" => true,
          "constraints" => %{"item_type" => "string"}
        })
      ]

      assert {:error, errors} =
               SchemaValidator.validate_payload(%{"tags" => ["ok", 42, "also_ok"]}, schema)

      assert Enum.any?(errors, &String.contains?(&1.field, "tags"))
    end

    test "accepts array at exact min_items boundary" do
      schema = [
        array_field("tags", "string", %{
          "required" => true,
          "constraints" => %{"item_type" => "string", "min_items" => 2}
        })
      ]

      assert {:ok, _} = SchemaValidator.validate_payload(%{"tags" => ["a", "b"]}, schema)
    end

    test "accepts array at exact max_items boundary" do
      schema = [
        array_field("tags", "string", %{
          "required" => true,
          "constraints" => %{"item_type" => "string", "max_items" => 2}
        })
      ]

      assert {:ok, _} = SchemaValidator.validate_payload(%{"tags" => ["a", "b"]}, schema)
    end
  end

  describe "validate_payload/2 — nested validation" do
    test "rejects nested object with invalid field" do
      schema = [
        object_field(
          "address",
          [
            string_field("city", %{"required" => true})
          ],
          %{"required" => true}
        )
      ]

      payload = %{"address" => %{"city" => 42}}
      assert {:error, errors} = SchemaValidator.validate_payload(payload, schema)
      assert Enum.any?(errors, &(&1.field == "address.city"))
    end

    test "rejects nested required field missing inside optional parent that is present" do
      schema = [
        object_field("address", [
          string_field("city", %{"required" => true})
        ])
      ]

      payload = %{"address" => %{}}
      assert {:error, errors} = SchemaValidator.validate_payload(payload, schema)
      assert Enum.any?(errors, &(&1.field == "address.city"))
    end

    test "reports full path in error message for nested field" do
      schema = [
        object_field(
          "meta",
          [
            object_field("details", [
              string_field("source", %{"required" => true})
            ])
          ],
          %{"required" => true}
        )
      ]

      payload = %{"meta" => %{"details" => %{}}}
      assert {:error, errors} = SchemaValidator.validate_payload(payload, schema)
      assert Enum.any?(errors, &(&1.field == "meta.details.source"))
    end

    test "reports full path for array item validation" do
      schema = [
        %{
          "name" => "items",
          "type" => "array",
          "required" => true,
          "constraints" => %{
            "item_type" => "object",
            "item_fields" => [string_field("name", %{"required" => true})]
          }
        }
      ]

      payload = %{"items" => [%{"name" => "ok"}, %{}]}
      assert {:error, errors} = SchemaValidator.validate_payload(payload, schema)
      assert Enum.any?(errors, &(&1.field == "items[1].name"))
    end
  end

  describe "validate_payload/2 — multiple errors" do
    test "returns all validation errors, not just the first one" do
      schema = [
        string_field("name", %{"required" => true}),
        integer_field("age", %{"required" => true}),
        string_field("email", %{"required" => true})
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{}, schema)
      assert length(errors) == 3
    end

    test "returns errors for multiple fields in single payload" do
      schema = [
        string_field("name", %{"required" => true}),
        integer_field("age", %{"required" => true, "constraints" => %{"min" => 0}})
      ]

      assert {:error, errors} =
               SchemaValidator.validate_payload(%{"name" => 42, "age" => -1}, schema)

      assert length(errors) == 2

      fields = Enum.map(errors, & &1.field)
      assert "name" in fields
      assert "age" in fields
    end
  end

  describe "validate_payload/2 — edge cases" do
    test "accepts payload when schema is empty list" do
      assert {:ok, %{"any" => "thing"}} =
               SchemaValidator.validate_payload(%{"any" => "thing"}, [])
    end

    test "accepts payload when schema is nil" do
      assert {:ok, %{"any" => "thing"}} =
               SchemaValidator.validate_payload(%{"any" => "thing"}, nil)
    end

    test "handles deeply nested object at max depth (3 levels)" do
      schema = [
        object_field(
          "l1",
          [
            object_field("l2", [
              object_field("l3", [string_field("value", %{"required" => true})])
            ])
          ],
          %{"required" => true}
        )
      ]

      payload = %{"l1" => %{"l2" => %{"l3" => %{"value" => "deep"}}}}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "handles unicode strings correctly" do
      schema = [
        string_field("name", %{"required" => true, "constraints" => %{"min_length" => 2}})
      ]

      payload = %{"name" => "João"}
      assert {:ok, ^payload} = SchemaValidator.validate_payload(payload, schema)
    end

    test "handles very long strings against max_length" do
      long_string = String.duplicate("a", 10_001)

      schema = [
        string_field("data", %{"required" => true, "constraints" => %{"max_length" => 10_000}})
      ]

      assert {:error, errors} = SchemaValidator.validate_payload(%{"data" => long_string}, schema)
      assert Enum.any?(errors, &(&1.field == "data"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # build_initial_state/1
  # ═══════════════════════════════════════════════════════════════════════════

  describe "build_initial_state/1" do
    test "builds state map from fields with initial values" do
      schema = [
        %{"name" => "counter", "type" => "integer", "initial_value" => 0},
        %{"name" => "label", "type" => "string", "initial_value" => "start"}
      ]

      assert %{"counter" => 0, "label" => "start"} = SchemaValidator.build_initial_state(schema)
    end

    test "uses nil for fields without initial_value" do
      schema = [
        %{"name" => "counter", "type" => "integer"},
        %{"name" => "label", "type" => "string", "initial_value" => "x"}
      ]

      result = SchemaValidator.build_initial_state(schema)
      assert result["counter"] == nil
      assert result["label"] == "x"
    end

    test "handles all types: string, integer, float, boolean, array, object" do
      schema = [
        %{"name" => "s", "type" => "string", "initial_value" => "hello"},
        %{"name" => "i", "type" => "integer", "initial_value" => 42},
        %{"name" => "f", "type" => "float", "initial_value" => 3.14},
        %{"name" => "b", "type" => "boolean", "initial_value" => true},
        %{"name" => "a", "type" => "array", "initial_value" => [1, 2, 3]},
        %{"name" => "o", "type" => "object", "initial_value" => %{"key" => "val"}}
      ]

      result = SchemaValidator.build_initial_state(schema)

      assert result == %{
               "s" => "hello",
               "i" => 42,
               "f" => 3.14,
               "b" => true,
               "a" => [1, 2, 3],
               "o" => %{"key" => "val"}
             }
    end

    test "preserves nested object structure in initial value" do
      schema = [
        %{
          "name" => "config",
          "type" => "object",
          "initial_value" => %{"db" => %{"host" => "localhost", "port" => 5432}}
        }
      ]

      result = SchemaValidator.build_initial_state(schema)
      assert result["config"]["db"]["host"] == "localhost"
      assert result["config"]["db"]["port"] == 5432
    end

    test "returns empty map for empty schema" do
      assert %{} = SchemaValidator.build_initial_state([])
    end

    test "returns empty map for nil schema" do
      assert %{} = SchemaValidator.build_initial_state(nil)
    end

    test "handles initial_value of 0 (falsy but valid)" do
      schema = [%{"name" => "count", "type" => "integer", "initial_value" => 0}]
      result = SchemaValidator.build_initial_state(schema)
      assert result["count"] == 0
    end

    test "handles initial_value of false (falsy but valid)" do
      schema = [%{"name" => "flag", "type" => "boolean", "initial_value" => false}]
      result = SchemaValidator.build_initial_state(schema)
      assert result["flag"] == false
    end

    test "handles initial_value of empty string" do
      schema = [%{"name" => "text", "type" => "string", "initial_value" => ""}]
      result = SchemaValidator.build_initial_state(schema)
      assert result["text"] == ""
    end

    test "handles initial_value of empty list" do
      schema = [%{"name" => "items", "type" => "array", "initial_value" => []}]
      result = SchemaValidator.build_initial_state(schema)
      assert result["items"] == []
    end

    test "handles initial_value of empty map" do
      schema = [%{"name" => "data", "type" => "object", "initial_value" => %{}}]
      result = SchemaValidator.build_initial_state(schema)
      assert result["data"] == %{}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # build_response/3
  # ═══════════════════════════════════════════════════════════════════════════

  describe "build_response/3" do
    test "maps state variables to response fields" do
      state = %{"counter" => 42, "items" => ["a", "b"]}

      response_schema = [
        integer_field("total", %{"required" => true}),
        array_field("collected", "string", %{"required" => true})
      ]

      mapping = [
        %{"response_field" => "total", "state_variable" => "counter"},
        %{"response_field" => "collected", "state_variable" => "items"}
      ]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response == %{"total" => 42, "collected" => ["a", "b"]}
    end

    test "renames state variable to different response field name" do
      state = %{"internal_count" => 99}
      response_schema = [integer_field("public_count")]
      mapping = [%{"response_field" => "public_count", "state_variable" => "internal_count"}]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response == %{"public_count" => 99}
    end

    test "maps multiple fields correctly" do
      state = %{"a" => 1, "b" => 2, "c" => 3}
      response_schema = [integer_field("x"), integer_field("y"), integer_field("z")]

      mapping = [
        %{"response_field" => "x", "state_variable" => "a"},
        %{"response_field" => "y", "state_variable" => "b"},
        %{"response_field" => "z", "state_variable" => "c"}
      ]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response == %{"x" => 1, "y" => 2, "z" => 3}
    end

    test "maps nested object from state" do
      state = %{"data" => %{"nested" => true}}
      response_schema = [object_field("result", [])]
      mapping = [%{"response_field" => "result", "state_variable" => "data"}]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response == %{"result" => %{"nested" => true}}
    end

    test "maps array from state" do
      state = %{"list" => [1, 2, 3]}
      response_schema = [array_field("items", "integer")]
      mapping = [%{"response_field" => "items", "state_variable" => "list"}]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response == %{"items" => [1, 2, 3]}
    end

    test "returns empty map when mapping is empty" do
      assert {:ok, %{}} = SchemaValidator.build_response(%{"x" => 1}, [], [])
    end

    test "returns empty map when mapping is nil" do
      assert {:ok, %{}} = SchemaValidator.build_response(%{"x" => 1}, [], nil)
    end

    test "returns error when mapped state variable does not exist in state" do
      state = %{"a" => 1}
      response_schema = [integer_field("x")]
      mapping = [%{"response_field" => "x", "state_variable" => "missing"}]

      assert {:error, errors} = SchemaValidator.build_response(state, response_schema, mapping)
      assert Enum.any?(errors, &(&1.field == "x"))
      assert Enum.any?(errors, &String.contains?(&1.message, "missing"))
    end

    test "returns error when multiple mappings reference non-existent variables" do
      state = %{}
      response_schema = [integer_field("x"), integer_field("y")]

      mapping = [
        %{"response_field" => "x", "state_variable" => "a"},
        %{"response_field" => "y", "state_variable" => "b"}
      ]

      assert {:error, errors} = SchemaValidator.build_response(state, response_schema, mapping)
      assert length(errors) == 2
    end

    test "handles state variable with nil value" do
      state = %{"val" => nil}
      response_schema = [string_field("result")]
      mapping = [%{"response_field" => "result", "state_variable" => "val"}]

      assert {:ok, %{"result" => nil}} =
               SchemaValidator.build_response(state, response_schema, mapping)
    end

    test "handles state variable with 0 value" do
      state = %{"count" => 0}
      response_schema = [integer_field("total")]
      mapping = [%{"response_field" => "total", "state_variable" => "count"}]

      assert {:ok, %{"total" => 0}} =
               SchemaValidator.build_response(state, response_schema, mapping)
    end

    test "handles state variable with false value" do
      state = %{"flag" => false}
      response_schema = [boolean_field("active")]
      mapping = [%{"response_field" => "active", "state_variable" => "flag"}]

      assert {:ok, %{"active" => false}} =
               SchemaValidator.build_response(state, response_schema, mapping)
    end

    test "handles state variable with empty string value" do
      state = %{"text" => ""}
      response_schema = [string_field("output")]
      mapping = [%{"response_field" => "output", "state_variable" => "text"}]

      assert {:ok, %{"output" => ""}} =
               SchemaValidator.build_response(state, response_schema, mapping)
    end

    test "preserves value types through mapping (no coercion)" do
      state = %{"num" => 42, "str" => "hello", "list" => [1, 2]}

      response_schema = [
        integer_field("a"),
        string_field("b"),
        array_field("c", "integer")
      ]

      mapping = [
        %{"response_field" => "a", "state_variable" => "num"},
        %{"response_field" => "b", "state_variable" => "str"},
        %{"response_field" => "c", "state_variable" => "list"}
      ]

      assert {:ok, response} = SchemaValidator.build_response(state, response_schema, mapping)
      assert response["a"] === 42
      assert response["b"] === "hello"
      assert response["c"] === [1, 2]
    end

    test "returns error when mapped value type mismatches response_schema type" do
      state = %{"count" => "not_an_integer"}
      response_schema = [integer_field("total", %{"required" => true})]
      mapping = [%{"response_field" => "total", "state_variable" => "count"}]

      assert {:error, errors} = SchemaValidator.build_response(state, response_schema, mapping)
      assert Enum.any?(errors, &(&1.field == "total" and String.contains?(&1.message, "integer")))
    end

    test "accepts nil mapped value regardless of declared type" do
      state = %{"val" => nil}
      response_schema = [string_field("result", %{"required" => true})]
      mapping = [%{"response_field" => "result", "state_variable" => "val"}]

      assert {:ok, %{"result" => nil}} =
               SchemaValidator.build_response(state, response_schema, mapping)
    end
  end
end
