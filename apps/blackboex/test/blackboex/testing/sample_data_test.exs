defmodule Blackboex.Testing.SampleDataTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.SampleData

  defp make_api(overrides \\ %{}) do
    Map.merge(
      %{
        param_schema: nil,
        example_request: nil,
        template_type: "computation"
      },
      overrides
    )
  end

  describe "generate/1 with param_schema" do
    test "generates string fields" do
      api = make_api(%{param_schema: %{"name" => "string"}})
      result = SampleData.generate(api)

      assert is_binary(result.happy_path["name"])
    end

    test "generates integer fields" do
      api = make_api(%{param_schema: %{"count" => "integer"}})
      result = SampleData.generate(api)

      assert is_integer(result.happy_path["count"])
    end

    test "generates number fields" do
      api = make_api(%{param_schema: %{"price" => "number"}})
      result = SampleData.generate(api)

      assert is_number(result.happy_path["price"])
    end

    test "generates boolean fields" do
      api = make_api(%{param_schema: %{"active" => "boolean"}})
      result = SampleData.generate(api)

      assert is_boolean(result.happy_path["active"])
    end

    test "generates edge cases" do
      api = make_api(%{param_schema: %{"name" => "string", "count" => "integer"}})
      result = SampleData.generate(api)

      assert is_list(result.edge_cases)
      assert result.edge_cases != []

      # Edge cases should include various problematic values
      all_values =
        result.edge_cases
        |> Enum.flat_map(fn m -> Map.values(m) end)

      # Should have empty strings
      assert "" in all_values
      # Should have nil values
      assert nil in all_values
    end

    test "generates invalid data" do
      api = make_api(%{param_schema: %{"name" => "string"}})
      result = SampleData.generate(api)

      assert is_list(result.invalid)
      assert result.invalid != []
    end

    test "edge cases include long strings" do
      api = make_api(%{param_schema: %{"name" => "string"}})
      result = SampleData.generate(api)

      long_values =
        result.edge_cases
        |> Enum.flat_map(fn m -> Map.values(m) end)
        |> Enum.filter(fn v -> is_binary(v) and String.length(v) > 1000 end)

      assert long_values != []
    end

    test "edge cases include unicode and special characters" do
      api = make_api(%{param_schema: %{"text" => "string"}})
      result = SampleData.generate(api)

      all_values =
        result.edge_cases
        |> Enum.flat_map(fn m -> Map.values(m) end)
        |> Enum.filter(&is_binary/1)

      has_unicode = Enum.any?(all_values, fn v -> String.contains?(v, "🎉") end)

      assert has_unicode
    end

    test "edge cases include SQL injection patterns" do
      api = make_api(%{param_schema: %{"input" => "string"}})
      result = SampleData.generate(api)

      all_values =
        result.edge_cases
        |> Enum.flat_map(fn m -> Map.values(m) end)
        |> Enum.filter(&is_binary/1)

      has_sql = Enum.any?(all_values, fn v -> String.contains?(v, "DROP") end)
      assert has_sql
    end

    test "edge cases include zero and negative numbers" do
      api = make_api(%{param_schema: %{"n" => "integer"}})
      result = SampleData.generate(api)

      all_values =
        result.edge_cases
        |> Enum.flat_map(fn m -> Map.values(m) end)

      assert 0 in all_values
      has_negative = Enum.any?(all_values, fn v -> is_integer(v) and v < 0 end)
      assert has_negative
    end
  end

  describe "generate/1 with example_request" do
    test "uses example_request as happy_path template" do
      api = make_api(%{example_request: %{"n" => 5, "name" => "test"}})
      result = SampleData.generate(api)

      assert result.happy_path == %{"n" => 5, "name" => "test"}
    end

    test "generates edge cases from example_request" do
      api = make_api(%{example_request: %{"n" => 5}})
      result = SampleData.generate(api)

      assert is_list(result.edge_cases)
      assert result.edge_cases != []
    end
  end

  describe "generate/1 without schema or example" do
    test "returns empty happy_path" do
      api = make_api()
      result = SampleData.generate(api)

      assert result.happy_path == %{}
    end

    test "returns empty edge_cases and invalid" do
      api = make_api()
      result = SampleData.generate(api)

      assert result.edge_cases == []
      assert result.invalid == []
    end
  end
end
