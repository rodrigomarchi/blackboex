defmodule Blackboex.Samples.ApiTemplates.ProductCatalog do
  @moduledoc """
  Template: Product Catalog

  Product catalog with search, filter by category, sort and pagination.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "product-catalog",
      name: "Product Catalog",
      description: "Product catalog with search, category filters and pagination",
      category: "Prototypes",
      template_type: "computation",
      icon: "shopping-bag",
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
        "query" => "string",
        "category" => "string",
        "sort" => "string",
        "page" => "integer",
        "limit" => "integer"
      },
      example_request: %{
        "category" => "electronics",
        "sort" => "price_asc",
        "page" => 1,
        "limit" => 5
      },
      example_response: %{
        "products" => [
          %{
            "id" => "p001",
            "name" => "Wireless Mouse",
            "category" => "electronics",
            "price" => 29.90,
            "stock" => 150
          }
        ],
        "meta" => %{
          "total" => 12,
          "page" => 1,
          "limit" => 5,
          "total_pages" => 3
        }
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
          %{"name" => "no filters returns all products paginated", "status" => "pass"},
          %{"name" => "category filter returns matching products", "status" => "pass"},
          %{"name" => "query search filters by name", "status" => "pass"},
          %{"name" => "sort price_asc returns ascending order", "status" => "pass"},
          %{"name" => "pagination returns correct page slice", "status" => "pass"},
          %{"name" => "invalid sort returns validation error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for product catalog endpoint."

      @doc "Processes a catalog search request and returns paginated products."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          {products, total} = Helpers.search(data)
          total_pages = ceil(total / data.limit)

          %{
            products: products,
            meta: %{
              total: total,
              page: data.page,
              limit: data.limit,
              total_pages: total_pages
            }
          }
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
      @moduledoc "Helper functions for product catalog search, filter, and sort."

      @catalog [
        %{id: "p001", name: "Wireless Mouse", category: "electronics", price: 29.90, stock: 150},
        %{id: "p002", name: "Mechanical Keyboard", category: "electronics", price: 189.90, stock: 45},
        %{id: "p003", name: "USB-C Hub", category: "electronics", price: 79.90, stock: 80},
        %{id: "p004", name: "Monitor 24\"", category: "electronics", price: 899.90, stock: 20},
        %{id: "p005", name: "Webcam HD", category: "electronics", price: 149.90, stock: 60},
        %{id: "p006", name: "Desk Lamp LED", category: "office", price: 49.90, stock: 200},
        %{id: "p007", name: "Ergonomic Chair", category: "office", price: 1299.90, stock: 10},
        %{id: "p008", name: "Notebook Stand", category: "office", price: 89.90, stock: 75},
        %{id: "p009", name: "Running Shoes", category: "sports", price: 299.90, stock: 30},
        %{id: "p010", name: "Yoga Mat", category: "sports", price: 59.90, stock: 120},
        %{id: "p011", name: "Water Bottle", category: "sports", price: 34.90, stock: 250},
        %{id: "p012", name: "Protein Powder", category: "sports", price: 179.90, stock: 40}
      ]

      @doc "Searches, filters, sorts and paginates the catalog."
      @spec search(map()) :: {[map()], integer()}
      def search(params) do
        results =
          @catalog
          |> filter_category(params.category)
          |> filter_query(params.query)
          |> sort_results(params.sort)

        total = length(results)
        offset = (params.page - 1) * params.limit
        page_results = results |> Enum.drop(offset) |> Enum.take(params.limit)
        {page_results, total}
      end

      defp filter_category(products, nil), do: products
      defp filter_category(products, ""), do: products
      defp filter_category(products, cat), do: Enum.filter(products, &(&1.category == cat))

      defp filter_query(products, nil), do: products
      defp filter_query(products, ""), do: products

      defp filter_query(products, q) do
        q_lower = String.downcase(q)
        Enum.filter(products, fn p -> String.contains?(String.downcase(p.name), q_lower) end)
      end

      defp sort_results(products, "price_asc"), do: Enum.sort_by(products, & &1.price)
      defp sort_results(products, "price_desc"), do: Enum.sort_by(products, & &1.price, :desc)
      defp sort_results(products, "name_asc"), do: Enum.sort_by(products, & &1.name)
      defp sort_results(products, "name_desc"), do: Enum.sort_by(products, & &1.name, :desc)
      defp sort_results(products, _), do: products
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for product catalog."

      use Blackboex.Schema
      import Ecto.Changeset

      @valid_sorts ["price_asc", "price_desc", "name_asc", "name_desc", "relevance"]

      @primary_key false
      embedded_schema do
        field :query, :string
        field :category, :string
        field :sort, :string
        field :page, :integer
        field :limit, :integer
      end

      @doc "Casts and validates catalog search request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:query, :category, :sort, :page, :limit])
        |> validate_inclusion(:sort, @valid_sorts,
          message: "must be one of: #{Enum.join(@valid_sorts, ", ")}"
        )
        |> validate_number(:page, greater_than: 0)
        |> validate_number(:limit, greater_than: 0, less_than_or_equal_to: 100)
        |> set_defaults()
      end

      defp set_defaults(changeset) do
        changeset
        |> put_default(:page, 1)
        |> put_default(:limit, 10)
        |> put_default(:sort, "relevance")
      end

      defp put_default(changeset, field, value) do
        if get_field(changeset, field) == nil,
          do: put_change(changeset, field, value),
          else: changeset
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the product catalog output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :products, {:array, :map}
        field :meta, :map
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      describe "handle/1" do
        test "no filters returns all products paginated" do
          result = Handler.handle(%{})
          assert is_list(result.products)
          assert result.meta.total > 0
          assert result.meta.page == 1
          assert result.meta.limit == 10
        end

        test "category filter returns only matching products" do
          result = Handler.handle(%{"category" => "electronics"})
          assert length(result.products) > 0
          Enum.each(result.products, fn p -> assert p.category == "electronics" end)
        end

        test "query search filters by name" do
          result = Handler.handle(%{"query" => "mouse"})
          assert length(result.products) > 0

          Enum.each(result.products, fn p ->
            assert String.contains?(String.downcase(p.name), "mouse")
          end)
        end

        test "sort price_asc returns ascending prices" do
          result = Handler.handle(%{"sort" => "price_asc"})
          prices = Enum.map(result.products, & &1.price)
          assert prices == Enum.sort(prices)
        end

        test "pagination returns correct page slice" do
          p1 = Handler.handle(%{"limit" => 3, "page" => 1})
          p2 = Handler.handle(%{"limit" => 3, "page" => 2})
          assert length(p1.products) == 3
          refute Enum.any?(p2.products, fn p -> p.id in Enum.map(p1.products, & &1.id) end)
        end

        test "invalid sort returns validation error" do
          result = Handler.handle(%{"sort" => "invalid"})
          assert result.error == "Validation failed"
          assert Map.has_key?(result.details, :sort)
        end

        test "meta total_pages is calculated correctly" do
          result = Handler.handle(%{"limit" => 5})
          assert result.meta.total_pages == ceil(result.meta.total / 5)
        end
      end

      test "Request.changeset accepts valid params" do
        cs = Request.changeset(%{"sort" => "price_asc", "page" => 1, "limit" => 10})
        assert cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # Product Catalog

    Product catalog with 12 items across 3 categories (electronics, office, sports).
    Supports text search, category filtering, sorting and pagination.

    ## Parameters

    | Field | Type | Required | Default | Description |
    |-------|------|-------------|--------|-----------|
    | `query` | string | no | none | Search by product name |
    | `category` | string | no | none | Filter by category |
    | `sort` | string | no | relevance | Sort order: `price_asc`, `price_desc`, `name_asc`, `name_desc` |
    | `page` | integer | no | 1 | Page (> 0) |
    | `limit` | integer | no | 10 | Items per page (1-100) |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/product-catalog \\
      -H "Content-Type: application/json" \\
      -d '{"category": "electronics", "sort": "price_asc", "page": 1, "limit": 5}'
    ```

    ## Example Response

    ```json
    {
      "products": [
        {"id": "p001", "name": "Wireless Mouse", "category": "electronics", "price": 29.90, "stock": 150}
      ],
      "meta": {"total": 5, "page": 1, "limit": 5, "total_pages": 1}
    }
    ```

    ## Customization

    Replace `@catalog` in `Helpers` with a real database query.
    The request/response structure remains compatible.
    """
  end
end
