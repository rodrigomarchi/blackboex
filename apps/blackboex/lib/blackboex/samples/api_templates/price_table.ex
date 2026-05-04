defmodule Blackboex.Samples.ApiTemplates.PriceTable do
  @moduledoc """
  Template: Price Table

  Price lookup with quantity-based discount rules.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "price-table",
      name: "Price Table",
      description: "Looks up prices with quantity-based discount rules",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "tag",
      method: "POST",
      files: %{
        handler: handler_code(),
        helpers: helpers_code(),
        request_schema: request_schema_code(),
        response_schema: response_schema_code(),
        test: test_code(),
        readme: readme_content()
      },
      param_schema: %{
        "product_id" => "string",
        "quantity" => "integer"
      },
      example_request: %{
        "product_id" => "PROD-001",
        "quantity" => 10
      },
      example_response: %{
        "unit_price" => 44.91,
        "discount_pct" => 10.0,
        "total_price" => 449.1
      },
      validation_report: %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [
          %{"name" => "known product qty 1 returns full price", "status" => "pass"},
          %{"name" => "qty 10 returns 10% discount", "status" => "pass"},
          %{"name" => "qty 50 returns 20% discount", "status" => "pass"},
          %{"name" => "unknown product returns error", "status" => "pass"},
          %{"name" => "zero quantity returns error", "status" => "pass"},
          %{"name" => "missing fields returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Looks up product prices and applies quantity discounts."

      @doc "Processes request and returns pricing result or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)

          case Helpers.lookup_price(data.product_id) do
            nil ->
              %{error: "Validation failed", details: %{product_id: ["product not found"]}}

            base_price ->
              discount = Helpers.discount_pct(data.quantity)
              unit_price = Float.round(base_price * (1 - discount / 100), 2)
              total = Float.round(unit_price * data.quantity, 2)
              %{unit_price: unit_price, discount_pct: discount, total_price: total}
          end
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
    end
    """
  end

  defp helpers_code do
    ~S"""
    defmodule Helpers do
      @moduledoc "Price lookup and discount calculation helpers."

      @catalog %{
        "PROD-001" => 49.90,
        "PROD-002" => 99.90,
        "PROD-003" => 199.90,
        "PROD-004" => 29.90,
        "PROD-005" => 149.90,
        "SVC-001" => 250.00,
        "SVC-002" => 500.00,
        "PKG-BASIC" => 79.90,
        "PKG-PRO" => 159.90,
        "PKG-ENT" => 399.90
      }

      @discount_tiers [
        {100, 25.0},
        {50, 20.0},
        {20, 15.0},
        {10, 10.0},
        {5, 5.0},
        {1, 0.0}
      ]

      @doc "Returns the base price for a product ID, or nil if not found."
      @spec lookup_price(String.t()) :: float() | nil
      def lookup_price(product_id), do: Map.get(@catalog, product_id)

      @doc "Returns the discount percentage for a given quantity."
      @spec discount_pct(integer()) :: float()
      def discount_pct(qty) do
        {_threshold, pct} = Enum.find(@discount_tiers, fn {t, _} -> qty >= t end)
        pct
      end

      @doc "Returns all product IDs in the catalog."
      @spec catalog_ids() :: [String.t()]
      def catalog_ids, do: Map.keys(@catalog)
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the price table API."
      use Blackboex.Schema

      embedded_schema do
        field :product_id, :string
        field :quantity, :integer
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:product_id, :quantity])
        |> validate_required([:product_id, :quantity])
        |> validate_length(:product_id, min: 1, max: 50)
        |> validate_number(:quantity, greater_than: 0)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the price table API."
      use Blackboex.Schema

      embedded_schema do
        field :unit_price, :float
        field :discount_pct, :float
        field :total_price, :float
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the price table handler."
      use ExUnit.Case

      describe "Request changeset validation" do
        test "accepts valid input" do
          changeset = Request.changeset(%{"product_id" => "PROD-001", "quantity" => 1})
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects zero quantity" do
          changeset = Request.changeset(%{"product_id" => "PROD-001", "quantity" => 0})
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "known product qty 1 returns full price with no discount" do
          result = Handler.handle(%{"product_id" => "PROD-001", "quantity" => 1})
          assert result.unit_price == 49.90
          assert result.discount_pct == 0.0
          assert result.total_price == 49.90
        end

        test "qty 10 returns 10% discount" do
          result = Handler.handle(%{"product_id" => "PROD-001", "quantity" => 10})
          assert result.discount_pct == 10.0
          assert result.unit_price < 49.90
          assert result.total_price == Float.round(result.unit_price * 10, 2)
        end

        test "qty 50 returns 20% discount" do
          result = Handler.handle(%{"product_id" => "PROD-001", "quantity" => 50})
          assert result.discount_pct == 20.0
        end
      end

      describe "error handling" do
        test "unknown product returns error" do
          result = Handler.handle(%{"product_id" => "UNKNOWN", "quantity" => 1})
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :product_id)
        end

        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Price Table

    Looks up product prices and applies progressive quantity discounts.
    Ideal as an agent tool for real-time quotes.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `product_id` | string | yes | Product ID in the catalog (for example: PROD-001) |
    | `quantity` | integer | yes | Desired quantity (must be > 0) |

    ## Available Products

    | ID | Base Price |
    |----|-----------|
    | PROD-001 | BRL 49.90 |
    | PROD-002 | BRL 99.90 |
    | PROD-003 | BRL 199.90 |
    | PROD-004 | BRL 29.90 |
    | PROD-005 | BRL 149.90 |
    | SVC-001 | BRL 250.00 |
    | SVC-002 | BRL 500.00 |
    | PKG-BASIC | BRL 79.90 |
    | PKG-PRO | BRL 159.90 |
    | PKG-ENT | BRL 399.90 |

    ## Discount Table

    | Quantity | Discount |
    |-----------|---------|
    | 1–4 | 0% |
    | 5–9 | 5% |
    | 10–19 | 10% |
    | 20–49 | 15% |
    | 50–99 | 20% |
    | 100+ | 25% |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/price-table \\
      -H "Content-Type: application/json" \\
      -d '{"product_id": "PROD-001", "quantity": 10}'
    ```

    ## Example Response

    ```json
    {
      "unit_price": 44.91,
      "discount_pct": 10.0,
      "total_price": 449.10
    }
    ```
    """
  end
end
