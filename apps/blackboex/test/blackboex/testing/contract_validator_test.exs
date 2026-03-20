defmodule Blackboex.Testing.ContractValidatorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.ContractValidator

  @spec_with_schema %{
    "openapi" => "3.1.0",
    "paths" => %{
      "/" => %{
        "post" => %{
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "type" => "object",
                    "properties" => %{
                      "result" => %{"type" => "integer"},
                      "message" => %{"type" => "string"}
                    },
                    "required" => ["result"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  describe "validate/2" do
    test "conforming response returns empty list" do
      response = %{
        status: 200,
        body: %{"result" => 42, "message" => "ok"}
      }

      assert ContractValidator.validate(response, @spec_with_schema) == []
    end

    test "missing required field returns violation" do
      response = %{
        status: 200,
        body: %{"message" => "ok"}
      }

      violations = ContractValidator.validate(response, @spec_with_schema)
      assert violations != []
      assert Enum.any?(violations, fn v -> v.type == :schema_violation end)
    end

    test "wrong type returns violation" do
      response = %{
        status: 200,
        body: %{"result" => "not_an_integer", "message" => "ok"}
      }

      violations = ContractValidator.validate(response, @spec_with_schema)
      assert violations != []
      assert Enum.any?(violations, fn v -> v.type == :schema_violation end)
    end

    test "unexpected status code returns violation" do
      response = %{
        status: 418,
        body: %{"error" => "I'm a teapot"}
      }

      violations = ContractValidator.validate(response, @spec_with_schema)
      assert violations != []
      assert Enum.any?(violations, fn v -> v.type == :undocumented_status end)
    end

    test "no schema in spec returns empty list for any valid response" do
      spec_no_schema = %{
        "openapi" => "3.1.0",
        "paths" => %{
          "/" => %{
            "post" => %{
              "responses" => %{
                "200" => %{"description" => "OK"}
              }
            }
          }
        }
      }

      response = %{status: 200, body: %{"anything" => "goes"}}
      assert ContractValidator.validate(response, spec_no_schema) == []
    end

    test "nil body returns empty list" do
      response = %{status: 200, body: nil}
      assert ContractValidator.validate(response, @spec_with_schema) == []
    end

    test "empty spec returns empty list" do
      response = %{status: 200, body: %{"result" => 42}}
      assert ContractValidator.validate(response, %{"openapi" => "3.1.0"}) == []
    end

    test "spec with no paths returns empty list" do
      response = %{status: 200, body: %{"result" => 42}}
      spec = %{"openapi" => "3.1.0", "paths" => %{}}
      assert ContractValidator.validate(response, spec) == []
    end
  end

  describe "extract_response_schema/2" do
    test "extracts schema for documented status" do
      schema = ContractValidator.extract_response_schema(@spec_with_schema, 200)
      assert schema["type"] == "object"
      assert schema["properties"]["result"]["type"] == "integer"
    end

    test "returns nil for undocumented status" do
      assert ContractValidator.extract_response_schema(@spec_with_schema, 500) == nil
    end
  end
end
