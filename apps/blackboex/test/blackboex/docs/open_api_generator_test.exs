defmodule Blackboex.Docs.OpenApiGeneratorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.OpenApiGenerator

  @base_api %Api{
    id: Ecto.UUID.generate(),
    name: "My Calculator API",
    slug: "my-calculator",
    description: "Performs calculations",
    template_type: "computation",
    method: "POST",
    status: "published",
    visibility: "public",
    requires_auth: true,
    param_schema: %{
      "number" => "integer",
      "operation" => "string"
    },
    example_request: %{"number" => 42, "operation" => "double"},
    example_response: %{"result" => 84}
  }

  describe "generate/2" do
    test "computation API returns spec with POST and GET" do
      spec =
        OpenApiGenerator.generate(@base_api,
          base_url: "https://api.example.com/api/org/my-calculator"
        )

      assert spec["openapi"] == "3.1.0"
      assert spec["info"]["title"] == "My Calculator API"
      assert spec["info"]["description"] == "Performs calculations"

      paths = spec["paths"]
      assert Map.has_key?(paths, "/")
      assert Map.has_key?(paths["/"], "post")
      assert Map.has_key?(paths["/"], "get")
    end

    test "crud API returns all REST operations" do
      api = %{@base_api | template_type: "crud"}
      spec = OpenApiGenerator.generate(api, base_url: "https://api.example.com/api/org/my-api")

      paths = spec["paths"]
      assert Map.has_key?(paths["/"], "get"), "missing GET /"
      assert Map.has_key?(paths["/"], "post"), "missing POST /"
      assert Map.has_key?(paths["/{id}"], "get"), "missing GET /{id}"
      assert Map.has_key?(paths["/{id}"], "put"), "missing PUT /{id}"
      assert Map.has_key?(paths["/{id}"], "delete"), "missing DELETE /{id}"
    end

    test "webhook API returns POST only" do
      api = %{@base_api | template_type: "webhook"}
      spec = OpenApiGenerator.generate(api, base_url: "https://api.example.com/api/org/my-api")

      paths = spec["paths"]
      assert Map.has_key?(paths["/"], "post")
      refute Map.has_key?(paths["/"], "get")
    end

    test "security schemes present when requires_auth is true" do
      spec = OpenApiGenerator.generate(@base_api)

      assert spec["components"]["securitySchemes"]["bearerAuth"]
      assert spec["security"] == [%{"bearerAuth" => []}]
    end

    test "no security when requires_auth is false" do
      api = %{@base_api | requires_auth: false}
      spec = OpenApiGenerator.generate(api)

      refute Map.has_key?(spec["components"] || %{}, "securitySchemes")
      assert spec["security"] == []
    end

    test "param_schema converted to request body schema" do
      spec = OpenApiGenerator.generate(@base_api)

      post_op = spec["paths"]["/"]["post"]
      request_body = post_op["requestBody"]
      assert request_body
      schema = request_body["content"]["application/json"]["schema"]
      assert schema["type"] == "object"
      assert schema["properties"]["number"]["type"] == "integer"
      assert schema["properties"]["operation"]["type"] == "string"
    end

    test "example_request and example_response included" do
      spec = OpenApiGenerator.generate(@base_api)

      post_op = spec["paths"]["/"]["post"]
      request_example = post_op["requestBody"]["content"]["application/json"]["example"]
      assert request_example == %{"number" => 42, "operation" => "double"}

      response_example =
        post_op["responses"]["200"]["content"]["application/json"]["example"]

      assert response_example == %{"result" => 84}
    end

    test "servers include base_url" do
      spec =
        OpenApiGenerator.generate(@base_api,
          base_url: "https://api.example.com/api/org/my-calculator"
        )

      assert [%{"url" => "https://api.example.com/api/org/my-calculator"}] = spec["servers"]
    end

    test "handles missing optional fields gracefully" do
      api = %Api{
        id: Ecto.UUID.generate(),
        name: "Minimal API",
        slug: "minimal",
        template_type: "computation",
        method: "POST",
        status: "published",
        visibility: "public",
        requires_auth: false,
        description: nil,
        param_schema: nil,
        example_request: nil,
        example_response: nil
      }

      spec = OpenApiGenerator.generate(api)
      assert spec["openapi"] == "3.1.0"
      assert spec["info"]["title"] == "Minimal API"
      assert spec["paths"]["/"]["post"]
    end

    test "spec is JSON-serializable" do
      spec = OpenApiGenerator.generate(@base_api)
      assert {:ok, _json} = Jason.encode(spec)
    end
  end

  describe "to_json/1" do
    test "returns valid JSON string" do
      spec = OpenApiGenerator.generate(@base_api)
      json = OpenApiGenerator.to_json(spec)
      assert is_binary(json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["openapi"] == "3.1.0"
    end
  end

  describe "to_yaml/1" do
    test "returns valid YAML string" do
      spec = OpenApiGenerator.generate(@base_api)
      yaml = OpenApiGenerator.to_yaml(spec)
      assert is_binary(yaml)
      assert String.contains?(yaml, "openapi:")
      assert String.contains?(yaml, "My Calculator API")
    end
  end
end
