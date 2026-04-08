defmodule Blackboex.Apis.VirtualFileTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.VirtualFile

  defp api_struct(overrides \\ %{}) do
    Map.merge(
      %Api{
        id: Ecto.UUID.generate(),
        name: "Test API",
        slug: "test-api",
        description: "A test API",
        template_type: "computation",
        method: "POST",
        param_schema: nil,
        example_request: nil,
        example_response: nil,
        validation_report: nil,
        requires_auth: false
      },
      overrides
    )
  end

  describe "build/1" do
    test "returns only openapi.json when api has no extra data" do
      api = api_struct()
      files = VirtualFile.build(api)

      assert length(files) == 1
      assert hd(files).path == "/docs/openapi.json"
    end

    test "returns only openapi.json when all optional fields are empty maps" do
      api =
        api_struct(%{
          param_schema: %{},
          example_request: %{},
          example_response: %{},
          validation_report: %{}
        })

      files = VirtualFile.build(api)

      assert length(files) == 1
      assert hd(files).path == "/docs/openapi.json"
    end

    test "generates openapi.json from api metadata" do
      api = api_struct(%{param_schema: %{"number" => "integer"}})

      files = VirtualFile.build(api)
      openapi = Enum.find(files, &(&1.path == "/docs/openapi.json"))

      assert openapi != nil
      assert openapi.read_only == true
      assert openapi.file_type == "generated"
      assert openapi.id == "virtual-openapi"

      decoded = Jason.decode!(openapi.content)
      assert decoded["openapi"] == "3.1.0"
      assert decoded["info"]["title"] == "Test API"
    end

    test "generates param_schema.json when param_schema is present" do
      api = api_struct(%{param_schema: %{"name" => "string", "age" => "integer"}})

      files = VirtualFile.build(api)
      schema = Enum.find(files, &(&1.path == "/docs/param_schema.json"))

      assert schema != nil
      assert schema.read_only == true
      assert schema.file_type == "generated"
      assert schema.id == "virtual-param-schema"

      decoded = Jason.decode!(schema.content)
      assert decoded["name"] == "string"
      assert decoded["age"] == "integer"
    end

    test "skips param_schema.json when param_schema is nil" do
      api = api_struct(%{param_schema: nil})
      files = VirtualFile.build(api)
      refute Enum.any?(files, &(&1.path == "/docs/param_schema.json"))
    end

    test "generates example request.json when example_request is present" do
      api = api_struct(%{example_request: %{"number" => 42}})

      files = VirtualFile.build(api)
      example = Enum.find(files, &(&1.path == "/docs/examples/request.json"))

      assert example != nil
      assert example.read_only == true
      assert example.file_type == "generated"
      assert example.id == "virtual-example-request"

      decoded = Jason.decode!(example.content)
      assert decoded["number"] == 42
    end

    test "generates example response.json when example_response is present" do
      api = api_struct(%{example_response: %{"result" => 100}})

      files = VirtualFile.build(api)
      example = Enum.find(files, &(&1.path == "/docs/examples/response.json"))

      assert example != nil
      assert example.read_only == true
      assert example.file_type == "generated"
      assert example.id == "virtual-example-response"

      decoded = Jason.decode!(example.content)
      assert decoded["result"] == 100
    end

    test "generates validation_report.json when validation_report is present" do
      report = %{
        "overall" => "pass",
        "compilation" => "pass",
        "format" => "pass",
        "tests" => "pass"
      }

      api = api_struct(%{validation_report: report})

      files = VirtualFile.build(api)
      vr = Enum.find(files, &(&1.path == "/docs/validation_report.json"))

      assert vr != nil
      assert vr.read_only == true
      assert vr.file_type == "generated"
      assert vr.id == "virtual-validation-report"

      decoded = Jason.decode!(vr.content)
      assert decoded["overall"] == "pass"
    end

    test "generates all files when all data is present" do
      api =
        api_struct(%{
          param_schema: %{"x" => "integer"},
          example_request: %{"x" => 1},
          example_response: %{"result" => 2},
          validation_report: %{"overall" => "pass"}
        })

      files = VirtualFile.build(api)

      paths = Enum.map(files, & &1.path) |> Enum.sort()

      assert paths == [
               "/docs/examples/request.json",
               "/docs/examples/response.json",
               "/docs/openapi.json",
               "/docs/param_schema.json",
               "/docs/validation_report.json"
             ]

      assert Enum.all?(files, &(&1.read_only == true))
      assert Enum.all?(files, &(&1.file_type == "generated"))
    end

    test "content is valid pretty-printed JSON" do
      api = api_struct(%{example_request: %{"nested" => %{"key" => "value"}}})

      files = VirtualFile.build(api)
      example = Enum.find(files, &(&1.path == "/docs/examples/request.json"))

      # Should be pretty-printed (contains newlines)
      assert String.contains?(example.content, "\n")
      assert {:ok, _} = Jason.decode(example.content)
    end
  end
end
