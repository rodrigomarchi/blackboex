defmodule Blackboex.CodeGen.SchemaExtractorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.SchemaExtractor

  # ---------------------------------------------------------------------------
  # Test modules at compile time — simulate LLM-generated API module structure
  # ---------------------------------------------------------------------------

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

  # Wrapper API modules with Request/Response submodules — used by extract/1
  defmodule FlatApi do
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :email, :string
        field :age, :integer
        field :score, :float
        field :active, :boolean
        field :meta, :map
      end
    end

    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :status, :string
        field :count, :integer
      end
    end
  end

  defmodule RequestOnlyApi do
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :name, :string
      end
    end
  end

  defmodule ResponseOnlyApi do
    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :result, :string
      end
    end
  end

  defmodule NestedApi do
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :coverage, :string
        embeds_one :vehicle, Vehicle
        embeds_many :items, Item
      end
    end

    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :premium_brl, :float
      end
    end
  end

  defmodule RequiredFieldsApi do
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :name, :string
        field :age, :integer
      end

      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:name, :age])
        |> validate_required([:name, :age])
      end
    end
  end

  # A plain module with no Ecto schema
  defmodule NoSchemaModule do
    def hello, do: :world
  end

  # ---------------------------------------------------------------------------
  # extract/1
  # ---------------------------------------------------------------------------

  describe "extract/1" do
    test "returns {:ok, map} with both request and response for a full API module" do
      assert {:ok, %{request: request, response: response}} = SchemaExtractor.extract(FlatApi)

      assert is_map(request)
      assert is_map(response)
      assert request.fields[:email] == :string
      assert request.fields[:age] == :integer
      assert request.fields[:score] == :float
      assert request.fields[:active] == :boolean
      assert request.fields[:meta] == :map
      assert response.fields[:status] == :string
      assert response.fields[:count] == :integer
    end

    test "returns {:ok, map} with only request when Response submodule is absent" do
      assert {:ok, %{request: request, response: nil}} =
               SchemaExtractor.extract(RequestOnlyApi)

      assert request.fields[:name] == :string
    end

    test "returns {:ok, map} with only response when Request submodule is absent" do
      assert {:ok, %{request: nil, response: response}} =
               SchemaExtractor.extract(ResponseOnlyApi)

      assert response.fields[:result] == :string
    end

    test "returns {:error, :no_schema} for module with no Request/Response submodules" do
      assert {:error, :no_schema} = SchemaExtractor.extract(NoSchemaModule)
    end

    test "extracts embeds_one and embeds_many in nested API module" do
      assert {:ok, %{request: request}} = SchemaExtractor.extract(NestedApi)

      assert request.fields[:coverage] == :string
      assert {:embed_one, Vehicle, nested_vehicle} = request.fields[:vehicle]
      assert nested_vehicle.fields[:year] == :integer
      assert {:embed_many, Item, nested_item} = request.fields[:items]
      assert nested_item.fields[:name] == :string
    end

    test "detects required fields via changeset/1 when available" do
      assert {:ok, %{request: request}} = SchemaExtractor.extract(RequiredFieldsApi)

      assert :name in request.required
      assert :age in request.required
    end

    test "required is empty list when no changeset/1 exported" do
      assert {:ok, %{request: request}} = SchemaExtractor.extract(FlatApi)
      assert request.required == []
    end
  end

  # ---------------------------------------------------------------------------
  # to_param_schema/1
  # ---------------------------------------------------------------------------

  describe "to_param_schema/1" do
    test "converts all basic field types to string representations" do
      {:ok, schema} = SchemaExtractor.extract(FlatApi)
      param_schema = SchemaExtractor.to_param_schema(schema)

      assert param_schema["email"] == "string"
      assert param_schema["age"] == "integer"
      assert param_schema["score"] == "float"
      assert param_schema["active"] == "boolean"
      assert param_schema["meta"] == "map"
    end

    test "converts embed_one to 'object' and embed_many to 'array'" do
      {:ok, schema} = SchemaExtractor.extract(NestedApi)
      param_schema = SchemaExtractor.to_param_schema(schema)

      assert param_schema["coverage"] == "string"
      assert param_schema["vehicle"] == "object"
      assert param_schema["items"] == "array"
    end

    test "returns empty map when schema has no request key" do
      assert SchemaExtractor.to_param_schema(%{}) == %{}
      assert SchemaExtractor.to_param_schema(nil) == %{}
      assert SchemaExtractor.to_param_schema(%{request: nil}) == %{}
    end

    test "handles embedded types directly in schema map" do
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

  # ---------------------------------------------------------------------------
  # to_json_schema/1
  # ---------------------------------------------------------------------------

  describe "to_json_schema/1" do
    test "produces valid JSON schema for flat fields" do
      {:ok, %{request: request}} = SchemaExtractor.extract(FlatApi)
      json = SchemaExtractor.to_json_schema(request)

      assert json["type"] == "object"
      assert json["properties"]["email"] == %{"type" => "string"}
      assert json["properties"]["age"] == %{"type" => "integer"}
      assert json["properties"]["score"] == %{"type" => "number"}
      assert json["properties"]["active"] == %{"type" => "boolean"}
      assert json["properties"]["meta"] == %{"type" => "object"}
    end

    test "does not include 'required' key when required list is empty" do
      {:ok, %{request: request}} = SchemaExtractor.extract(FlatApi)
      json = SchemaExtractor.to_json_schema(request)

      refute Map.has_key?(json, "required")
    end

    test "includes 'required' key when required fields are present" do
      {:ok, %{request: request}} = SchemaExtractor.extract(RequiredFieldsApi)
      json = SchemaExtractor.to_json_schema(request)

      assert "name" in json["required"]
      assert "age" in json["required"]
    end

    test "nested embed_one produces inline object schema" do
      {:ok, %{request: request}} = SchemaExtractor.extract(NestedApi)
      json = SchemaExtractor.to_json_schema(request)

      vehicle_schema = json["properties"]["vehicle"]
      assert vehicle_schema["type"] == "object"
      assert vehicle_schema["properties"]["year"] == %{"type" => "integer"}
    end

    test "nested embed_many produces array schema with items" do
      {:ok, %{request: request}} = SchemaExtractor.extract(NestedApi)
      json = SchemaExtractor.to_json_schema(request)

      items_schema = json["properties"]["items"]
      assert items_schema["type"] == "array"
      assert items_schema["items"]["type"] == "object"
      assert items_schema["items"]["properties"]["name"] == %{"type" => "string"}
    end

    test "handles embed_one with nil nested schema (fallback to object)" do
      schema = %{
        fields: %{thing: {:embed_one, NoSchemaModule, nil}},
        required: []
      }

      json = SchemaExtractor.to_json_schema(schema)
      assert json["properties"]["thing"] == %{"type" => "object"}
    end

    test "handles embed_many with nil nested schema (fallback to array of objects)" do
      schema = %{
        fields: %{things: {:embed_many, NoSchemaModule, nil}},
        required: []
      }

      json = SchemaExtractor.to_json_schema(schema)

      assert json["properties"]["things"] == %{
               "type" => "array",
               "items" => %{"type" => "object"}
             }
    end

    test "handles unknown atom type with fallback to string" do
      schema = %{
        fields: %{x: :utc_datetime, y: :date, z: :time, w: :naive_datetime},
        required: []
      }

      json = SchemaExtractor.to_json_schema(schema)

      assert json["properties"]["x"] == %{"type" => "string"}
      assert json["properties"]["y"] == %{"type" => "string"}
      assert json["properties"]["z"] == %{"type" => "string"}
      assert json["properties"]["w"] == %{"type" => "string"}
    end

    test "handles unknown non-atom type with fallback to string" do
      schema = %{fields: %{x: "weird_type"}, required: []}
      json = SchemaExtractor.to_json_schema(schema)
      assert json["properties"]["x"] == %{"type" => "string"}
    end
  end

  # ---------------------------------------------------------------------------
  # generate_example/1
  # ---------------------------------------------------------------------------

  describe "generate_example/1" do
    test "returns empty map for nil" do
      assert SchemaExtractor.generate_example(nil) == %{}
    end

    test "uses name-based smart values for well-known field names" do
      schema = %{fields: %{age: :integer, email: :string, year: :integer, value_brl: :float}}
      example = SchemaExtractor.generate_example(schema)

      assert example["age"] == 30
      assert example["email"] == "user@example.com"
      assert example["year"] == 2023
      assert example["value_brl"] == 10_000.00
    end

    test "uses type-based fallback for unknown field names" do
      schema = %{fields: %{foo: :string, bar: :integer, baz: :boolean, qux: :float}}
      example = SchemaExtractor.generate_example(schema)

      assert example["foo"] == "example"
      assert example["bar"] == 42
      assert example["baz"] == true
      assert example["qux"] == 3.14
    end

    test "type fallback for :map returns empty map" do
      schema = %{fields: %{data: :map}}
      assert SchemaExtractor.generate_example(schema)["data"] == %{}
    end

    test "type fallback for :decimal returns float" do
      # "amount" matches the price pattern, so use a neutral field name
      schema = %{fields: %{decimal_field: :decimal}}
      assert SchemaExtractor.generate_example(schema)["decimal_field"] == 3.14
    end

    test "type fallback for :binary returns empty string" do
      schema = %{fields: %{blob: :binary}}
      assert SchemaExtractor.generate_example(schema)["blob"] == ""
    end

    test "type fallback for :date returns ISO8601 date string" do
      schema = %{fields: %{dob: :date}}
      val = SchemaExtractor.generate_example(schema)["dob"]
      assert is_binary(val)
      assert String.match?(val, ~r/^\d{4}-\d{2}-\d{2}$/)
    end

    test "type fallback for :time returns ISO8601 time string" do
      schema = %{fields: %{at: :time}}
      val = SchemaExtractor.generate_example(schema)["at"]
      assert is_binary(val)
      assert String.match?(val, ~r/^\d{2}:\d{2}:\d{2}/)
    end

    test "type fallback for :utc_datetime returns ISO8601 datetime string" do
      schema = %{fields: %{ts: :utc_datetime}}
      val = SchemaExtractor.generate_example(schema)["ts"]
      assert is_binary(val)
      assert String.contains?(val, "T")
    end

    test "type fallback for :naive_datetime returns ISO8601 datetime string" do
      schema = %{fields: %{ts: :naive_datetime}}
      val = SchemaExtractor.generate_example(schema)["ts"]
      assert is_binary(val)
      assert String.contains?(val, "T")
    end

    test "type fallback for unknown type returns 'value'" do
      schema = %{fields: %{weird: :unknown_type}}
      assert SchemaExtractor.generate_example(schema)["weird"] == "value"
    end

    test "pattern-based name matching for price-like fields" do
      schema = %{fields: %{total_price: :float, monthly_premium: :float, fee: :float}}
      example = SchemaExtractor.generate_example(schema)

      assert example["total_price"] == 10_000
      assert example["monthly_premium"] == 10_000
      assert example["fee"] == 10_000
    end

    test "pattern-based name matching for is_/has_ boolean fields" do
      schema = %{fields: %{is_active: :boolean, has_claims: :boolean, can_drive: :boolean}}
      example = SchemaExtractor.generate_example(schema)

      assert example["is_active"] == true
      assert example["has_claims"] == true
      assert example["can_drive"] == true
    end

    test "generates nested examples for embed_one with nested schema" do
      schema = %{
        fields: %{
          coverage: :string,
          vehicle:
            {:embed_one, Vehicle,
             %{fields: %{year: :integer, category: :string, value_brl: :float}, required: []}}
        }
      }

      example = SchemaExtractor.generate_example(schema)

      assert example["coverage"] == "comprehensive"
      assert is_map(example["vehicle"])
      assert example["vehicle"]["year"] == 2023
      assert example["vehicle"]["value_brl"] == 10_000.00
    end

    test "generates empty map for embed_one with nil nested schema" do
      schema = %{fields: %{thing: {:embed_one, NoSchemaModule, nil}}}
      assert SchemaExtractor.generate_example(schema)["thing"] == %{}
    end

    test "generates array example for embed_many with nested schema" do
      schema = %{
        fields: %{
          items:
            {:embed_many, Item,
             %{fields: %{name: :string, quantity: :integer, price: :float}, required: []}}
        }
      }

      example = SchemaExtractor.generate_example(schema)
      assert is_list(example["items"])
      assert length(example["items"]) == 1
      [item] = example["items"]
      assert item["name"] == "John Doe"
      assert item["quantity"] == 3
    end

    test "generates array with empty map for embed_many with nil nested schema" do
      schema = %{fields: %{things: {:embed_many, NoSchemaModule, nil}}}
      assert SchemaExtractor.generate_example(schema)["things"] == [%{}]
    end

    test "generates examples from real extracted schema end-to-end" do
      {:ok, %{request: request, response: response}} = SchemaExtractor.extract(FlatApi)

      req_example = SchemaExtractor.generate_example(request)
      resp_example = SchemaExtractor.generate_example(response)

      assert req_example["email"] == "user@example.com"
      assert req_example["age"] == 30
      assert req_example["active"] == true
      assert req_example["meta"] == %{}
      # "status" maps to "active" via @name_values smart lookup
      assert resp_example["status"] == "active"
      assert resp_example["count"] == 3
    end
  end

  # ---------------------------------------------------------------------------
  # extract_embedded_schema with nested embeds (via helpers)
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Private helpers (test-local)
  # ---------------------------------------------------------------------------

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
