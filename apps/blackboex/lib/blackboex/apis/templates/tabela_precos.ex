defmodule Blackboex.Apis.Templates.TabelaPrecos do
  @moduledoc """
  Template: Tabela de Preços

  Price lookup with quantity-based discount rules.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "tabela-precos",
      name: "Tabela de Preços",
      description: "Lookup de preços com regras de desconto por quantidade",
      category: "AI Agent Tools",
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
        "produto_id" => "string",
        "quantidade" => "integer"
      },
      example_request: %{
        "produto_id" => "PROD-001",
        "quantidade" => 10
      },
      example_response: %{
        "preco_unitario" => 44.91,
        "desconto_pct" => 10.0,
        "preco_total" => 449.1
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

          case Helpers.lookup_price(data.produto_id) do
            nil ->
              %{error: "Validation failed", details: %{produto_id: ["product not found"]}}

            base_price ->
              discount = Helpers.discount_pct(data.quantidade)
              unit_price = Float.round(base_price * (1 - discount / 100), 2)
              total = Float.round(unit_price * data.quantidade, 2)
              %{preco_unitario: unit_price, desconto_pct: discount, preco_total: total}
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
      def lookup_price(produto_id), do: Map.get(@catalog, produto_id)

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
        field :produto_id, :string
        field :quantidade, :integer
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:produto_id, :quantidade])
        |> validate_required([:produto_id, :quantidade])
        |> validate_length(:produto_id, min: 1, max: 50)
        |> validate_number(:quantidade, greater_than: 0)
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
        field :preco_unitario, :float
        field :desconto_pct, :float
        field :preco_total, :float
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
          changeset = Request.changeset(%{"produto_id" => "PROD-001", "quantidade" => 1})
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects zero quantity" do
          changeset = Request.changeset(%{"produto_id" => "PROD-001", "quantidade" => 0})
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "known product qty 1 returns full price with no discount" do
          result = Handler.handle(%{"produto_id" => "PROD-001", "quantidade" => 1})
          assert result.preco_unitario == 49.90
          assert result.desconto_pct == 0.0
          assert result.preco_total == 49.90
        end

        test "qty 10 returns 10% discount" do
          result = Handler.handle(%{"produto_id" => "PROD-001", "quantidade" => 10})
          assert result.desconto_pct == 10.0
          assert result.preco_unitario < 49.90
          assert result.preco_total == Float.round(result.preco_unitario * 10, 2)
        end

        test "qty 50 returns 20% discount" do
          result = Handler.handle(%{"produto_id" => "PROD-001", "quantidade" => 50})
          assert result.desconto_pct == 20.0
        end
      end

      describe "error handling" do
        test "unknown product returns error" do
          result = Handler.handle(%{"produto_id" => "UNKNOWN", "quantidade" => 1})
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :produto_id)
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
    # Tabela de Preços

    Consulta preços de produtos com aplicação automática de descontos progressivos
    por quantidade. Ideal como tool de agente para cotações em tempo real.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `produto_id` | string | sim | ID do produto no catálogo (ex: PROD-001) |
    | `quantidade` | integer | sim | Quantidade desejada (deve ser > 0) |

    ## Produtos Disponíveis

    | ID | Preço Base |
    |----|-----------|
    | PROD-001 | R$ 49,90 |
    | PROD-002 | R$ 99,90 |
    | PROD-003 | R$ 199,90 |
    | PROD-004 | R$ 29,90 |
    | PROD-005 | R$ 149,90 |
    | SVC-001 | R$ 250,00 |
    | SVC-002 | R$ 500,00 |
    | PKG-BASIC | R$ 79,90 |
    | PKG-PRO | R$ 159,90 |
    | PKG-ENT | R$ 399,90 |

    ## Tabela de Descontos

    | Quantidade | Desconto |
    |-----------|---------|
    | 1–4 | 0% |
    | 5–9 | 5% |
    | 10–19 | 10% |
    | 20–49 | 15% |
    | 50–99 | 20% |
    | 100+ | 25% |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/tabela-precos \\
      -H "Content-Type: application/json" \\
      -d '{"produto_id": "PROD-001", "quantidade": 10}'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "preco_unitario": 44.91,
      "desconto_pct": 10.0,
      "preco_total": 449.10
    }
    ```
    """
  end
end
