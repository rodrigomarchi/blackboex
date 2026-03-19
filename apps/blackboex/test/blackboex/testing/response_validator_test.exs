defmodule Blackboex.Testing.ResponseValidatorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.ResponseValidator

  describe "validate/2 without schema" do
    test "returns empty list when schema is nil" do
      response = %{status: 200, body: ~s({"ok": true}), headers: %{}}
      assert ResponseValidator.validate(response, nil) == []
    end

    test "returns empty list when schema is empty map" do
      response = %{status: 200, body: ~s({"ok": true}), headers: %{}}
      assert ResponseValidator.validate(response, %{}) == []
    end
  end

  describe "validate/2 status code" do
    test "no violation for 2xx status" do
      response = %{status: 200, body: "{}", headers: %{}}
      schema = %{"result" => "string"}
      violations = ResponseValidator.validate(response, schema)
      refute Enum.any?(violations, fn v -> v.type == :unexpected_status end)
    end

    test "violation for 5xx status" do
      response = %{status: 500, body: "{}", headers: %{}}
      schema = %{"result" => "string"}
      violations = ResponseValidator.validate(response, schema)
      assert Enum.any?(violations, fn v -> v.type == :unexpected_status end)
    end

    test "violation for 4xx status" do
      response = %{status: 400, body: "{}", headers: %{}}
      schema = %{"result" => "string"}
      violations = ResponseValidator.validate(response, schema)
      assert Enum.any?(violations, fn v -> v.type == :unexpected_status end)
    end
  end

  describe "validate/2 missing fields" do
    test "detects missing field in response body" do
      response = %{status: 200, body: ~s({"name": "test"}), headers: %{}}
      schema = %{"name" => "string", "age" => "integer"}
      violations = ResponseValidator.validate(response, schema)

      missing = Enum.find(violations, fn v -> v.type == :missing_field end)
      assert missing
      assert missing.path == "age"
    end

    test "no violation when all fields present" do
      response = %{status: 200, body: ~s({"name": "test", "age": 25}), headers: %{}}
      schema = %{"name" => "string", "age" => "integer"}
      violations = ResponseValidator.validate(response, schema)
      refute Enum.any?(violations, fn v -> v.type == :missing_field end)
    end
  end

  describe "validate/2 wrong types" do
    test "detects string where integer expected" do
      response = %{status: 200, body: ~s({"count": "not_a_number"}), headers: %{}}
      schema = %{"count" => "integer"}
      violations = ResponseValidator.validate(response, schema)

      type_error = Enum.find(violations, fn v -> v.type == :wrong_type end)
      assert type_error
      assert type_error.path == "count"
    end

    test "detects integer where string expected" do
      response = %{status: 200, body: ~s({"name": 42}), headers: %{}}
      schema = %{"name" => "string"}
      violations = ResponseValidator.validate(response, schema)

      assert Enum.any?(violations, fn v -> v.type == :wrong_type and v.path == "name" end)
    end

    test "no violation when types match" do
      response = %{status: 200, body: ~s({"name": "test", "count": 5}), headers: %{}}
      schema = %{"name" => "string", "count" => "integer"}
      violations = ResponseValidator.validate(response, schema)
      refute Enum.any?(violations, fn v -> v.type == :wrong_type end)
    end
  end

  describe "validate/2 with non-JSON body" do
    test "returns parse error violation for invalid JSON" do
      response = %{status: 200, body: "not json at all", headers: %{}}
      schema = %{"result" => "string"}
      violations = ResponseValidator.validate(response, schema)

      assert Enum.any?(violations, fn v -> v.type == :invalid_json end)
    end
  end

  describe "validate/2 valid response" do
    test "returns empty list for fully valid response" do
      response = %{
        status: 200,
        body: ~s({"result": 42, "message": "success"}),
        headers: %{}
      }

      schema = %{"result" => "integer", "message" => "string"}
      assert ResponseValidator.validate(response, schema) == []
    end
  end
end
