defmodule Blackboex.CodeGen.SchemaExtractorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.SchemaExtractor

  # Define test modules with embedded schemas to simulate LLM-generated code

  defmodule FlatRequest do
    use Blackboex.Schema

    embedded_schema do
      field :name, :string
      field :age, :integer
      field :active, :boolean
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:name, :age, :active])
      |> validate_required([:name, :age])
    end
  end

  defmodule Vehicle do
    use Blackboex.Schema

    embedded_schema do
      field :year, :integer
      field :category, :string
      field :value_brl, :float
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:year, :category, :value_brl])
      |> validate_required([:year, :category, :value_brl])
    end
  end

  defmodule Driver do
    use Blackboex.Schema

    embedded_schema do
      field :age, :integer
      field :license_years, :integer
      field :claims_last_3y, :integer
      field :zip_prefix, :string
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:age, :license_years, :claims_last_3y, :zip_prefix])
      |> validate_required([:age, :license_years])
    end
  end

  defmodule NestedRequest do
    use Blackboex.Schema

    embedded_schema do
      field :coverage, :string
      embeds_one :vehicle, Vehicle
      embeds_one :driver, Driver
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:coverage])
      |> cast_embed(:vehicle, required: true)
      |> cast_embed(:driver, required: true)
      |> validate_required([:coverage])
    end
  end

  defmodule Item do
    use Blackboex.Schema

    embedded_schema do
      field :name, :string
      field :quantity, :integer
      field :price, :float
    end
  end

  defmodule OrderRequest do
    use Blackboex.Schema

    embedded_schema do
      field :customer_name, :string
      embeds_many :items, Item
    end
  end

  # Wrapper modules to simulate compiled API module structure (Module.Request)
  defmodule FlatApi do
    defmodule Request, do: (use Blackboex.Schema; embedded_schema do field(:email, :string); field(:age, :integer) end)
    defmodule Response, do: (use Blackboex.Schema; embedded_schema do field(:status, :string) end)
  end

  describe "generate_example/1" do
    test "generates smart values based on field names" do
      schema = %{fields: %{age: :integer, email: :string, year: :integer, value_brl: :float}}
      example = SchemaExtractor.generate_example(schema)

      assert example["age"] == 30
      assert example["email"] == "user@example.com"
      assert example["year"] == 2023
      assert example["value_brl"] == 10_000.00
    end

    test "falls back to type-based values for unknown field names" do
      schema = %{fields: %{foo: :string, bar: :integer, baz: :boolean}}
      example = SchemaExtractor.generate_example(schema)

      assert example["foo"] == "example"
      assert example["bar"] == 42
      assert example["baz"] == true
    end

    test "generates nested examples for embeds_one" do
      schema = %{
        fields: %{
          coverage: :string,
          vehicle: {:embed_one, Vehicle, %{fields: %{year: :integer, category: :string, value_brl: :float}, required: []}},
          driver: {:embed_one, Driver, %{fields: %{age: :integer, license_years: :integer, zip_prefix: :string}, required: []}}
        }
      }

      example = SchemaExtractor.generate_example(schema)

      assert example["coverage"] == "comprehensive"
      assert is_map(example["vehicle"])
      assert example["vehicle"]["year"] == 2023
      assert example["vehicle"]["category"] == "standard"
      assert example["vehicle"]["value_brl"] == 10_000.00
      assert is_map(example["driver"])
      assert example["driver"]["age"] == 30
      assert example["driver"]["license_years"] == 5
      assert example["driver"]["zip_prefix"] == "01"
    end

    test "generates array examples for embeds_many" do
      schema = %{
        fields: %{
          customer_name: :string,
          items: {:embed_many, Item, %{fields: %{name: :string, quantity: :integer, price: :float}, required: []}}
        }
      }

      example = SchemaExtractor.generate_example(schema)

      assert is_list(example["items"])
      assert length(example["items"]) == 1
      [item] = example["items"]
      assert item["name"] == "John Doe"
      assert item["quantity"] == 3
    end

    test "returns empty map for nil" do
      assert SchemaExtractor.generate_example(nil) == %{}
    end
  end

  describe "extract_embedded_schema via extract/1 with real modules" do
    test "extracts flat schema fields" do
      {:ok, %{request: request}} = SchemaExtractor.extract(FlatApi)

      assert request.fields[:email] == :string
      assert request.fields[:age] == :integer
    end
  end

  describe "extract_embedded_schema with nested embeds" do
    test "extracts embeds_one as nested schema info" do
      schema = extract_test_schema(NestedRequest)

      assert schema.fields[:coverage] == :string
      assert {:embed_one, Vehicle, nested_vehicle} = schema.fields[:vehicle]
      assert nested_vehicle.fields[:year] == :integer
      assert nested_vehicle.fields[:category] == :string
      assert nested_vehicle.fields[:value_brl] == :float

      assert {:embed_one, Driver, nested_driver} = schema.fields[:driver]
      assert nested_driver.fields[:age] == :integer
      assert nested_driver.fields[:license_years] == :integer
    end

    test "extracts embeds_many" do
      schema = extract_test_schema(OrderRequest)

      assert schema.fields[:customer_name] == :string
      assert {:embed_many, Item, nested_item} = schema.fields[:items]
      assert nested_item.fields[:name] == :string
      assert nested_item.fields[:quantity] == :integer
      assert nested_item.fields[:price] == :float
    end
  end

  describe "to_param_schema/1" do
    test "handles embedded types" do
      schema = %{
        request: %{
          fields: %{
            coverage: :string,
            vehicle: {:embed_one, Vehicle, %{fields: %{}, required: []}},
            items: {:embed_many, Item, %{fields: %{}, required: []}}
          },
          required: []
        }
      }

      param_schema = SchemaExtractor.to_param_schema(schema)

      assert param_schema["coverage"] == "string"
      assert param_schema["vehicle"] == "object"
      assert param_schema["items"] == "array"
    end
  end

  describe "to_json_schema/1" do
    test "handles embedded types with nested properties" do
      nested_vehicle = %{
        fields: %{year: :integer, category: :string},
        required: [:year]
      }

      schema = %{
        fields: %{
          coverage: :string,
          vehicle: {:embed_one, Vehicle, nested_vehicle}
        },
        required: [:coverage]
      }

      json_schema = SchemaExtractor.to_json_schema(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["coverage"] == %{"type" => "string"}
      assert json_schema["properties"]["vehicle"]["type"] == "object"
      assert json_schema["properties"]["vehicle"]["properties"]["year"] == %{"type" => "integer"}
      assert json_schema["required"] == ["coverage"]
    end
  end

  # Helper to extract schema from a test module directly
  defp extract_test_schema(module) do
    fields = module.__schema__(:fields)
    embeds = module.__schema__(:embeds)

    embed_map =
      Map.new(embeds, fn embed_field ->
        embed_type = module.__schema__(:embed, embed_field)

        case embed_type do
          %Ecto.Embedded{cardinality: :one, related: related_mod} ->
            nested = extract_nested(related_mod)
            {embed_field, {:embed_one, related_mod, nested}}

          %Ecto.Embedded{cardinality: :many, related: related_mod} ->
            nested = extract_nested(related_mod)
            {embed_field, {:embed_many, related_mod, nested}}
        end
      end)

    types =
      fields
      |> Enum.reject(&(&1 in Map.keys(embed_map)))
      |> Map.new(fn f -> {f, module.__schema__(:type, f)} end)
      |> Map.merge(embed_map)

    %{fields: types, required: []}
  end

  defp extract_nested(mod) do
    fields = mod.__schema__(:fields)
    types = Map.new(fields, fn f -> {f, mod.__schema__(:type, f)} end)
    %{fields: types, required: []}
  end
end
