defmodule Blackboex.Apis.Templates.PaymentGateway do
  @moduledoc """
  Template: Payment Gateway Mock

  Simulates charge creation and status lookup for testing payment flows
  without connecting to a real payment processor.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "payment-gateway",
      name: "Payment Gateway Mock",
      description: "Simula criação de cobrança e consulta de status para testes de pagamento",
      category: "Mocks",
      icon: "dollar-sign",
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
        "amount" => "number",
        "currency" => "string",
        "customer_id" => "string"
      },
      example_request: %{
        "amount" => 2990,
        "currency" => "BRL",
        "customer_id" => "cus_mock_abc123"
      },
      example_response: %{
        "charge_id" => "ch_mock_a1b2c3d4",
        "status" => "succeeded",
        "amount" => 2990,
        "currency" => "BRL",
        "created_at" => "2024-01-15T10:30:00Z"
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
          %{"name" => "valid charge returns succeeded status", "status" => "pass"},
          %{"name" => "charge_id has ch_mock_ prefix", "status" => "pass"},
          %{"name" => "missing amount returns validation error", "status" => "pass"},
          %{"name" => "missing currency returns validation error", "status" => "pass"},
          %{"name" => "missing customer_id returns validation error", "status" => "pass"},
          %{"name" => "zero amount returns validation error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for payment gateway mock endpoint."

      @doc "Processes a charge creation request and returns a mock charge."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          Helpers.create_mock_charge(data)
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
      @moduledoc "Helper functions for building mock payment charges."

      @charge_prefix "ch_mock_"

      @doc "Creates a deterministic mock charge from validated request data."
      @spec create_mock_charge(map()) :: map()
      def create_mock_charge(data) do
        hash =
          (data.customer_id <> Float.to_string(data.amount * 1.0))
          |> String.to_charlist()
          |> Enum.reduce(0, fn c, acc -> rem(acc * 31 + c, 0xFFFFFFFF) end)

        charge_id = "#{@charge_prefix}#{Integer.to_string(hash, 16) |> String.downcase()}"
        created_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

        %{
          charge_id: charge_id,
          status: "succeeded",
          amount: data.amount,
          currency: String.upcase(data.currency),
          created_at: created_at
        }
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for payment gateway mock."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :amount, :integer
        field :currency, :string
        field :customer_id, :string
      end

      @doc "Casts and validates charge request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:amount, :currency, :customer_id])
        |> validate_required([:amount, :currency, :customer_id])
        |> validate_number(:amount, greater_than: 0, message: "must be greater than 0")
        |> validate_length(:currency, min: 3, max: 3)
        |> validate_length(:customer_id, min: 1, max: 200)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the payment gateway mock output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :charge_id, :string
        field :status, :string
        field :amount, :integer
        field :currency, :string
        field :created_at, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      @valid_params %{
        "amount" => 2990,
        "currency" => "BRL",
        "customer_id" => "cus_mock_abc123"
      }

      test "valid charge returns succeeded status" do
        result = Handler.handle(@valid_params)
        assert result.status == "succeeded"
        assert result.amount == 2990
        assert result.currency == "BRL"
        assert is_binary(result.created_at)
      end

      test "charge_id has ch_mock_ prefix" do
        result = Handler.handle(@valid_params)
        assert String.starts_with?(result.charge_id, "ch_mock_")
      end

      test "missing amount returns validation error" do
        result = Handler.handle(Map.delete(@valid_params, "amount"))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :amount)
      end

      test "missing currency returns validation error" do
        result = Handler.handle(Map.delete(@valid_params, "currency"))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :currency)
      end

      test "missing customer_id returns validation error" do
        result = Handler.handle(Map.delete(@valid_params, "customer_id"))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :customer_id)
      end

      test "zero amount returns validation error" do
        result = Handler.handle(Map.put(@valid_params, "amount", 0))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :amount)
      end

      test "Request.changeset validates required fields" do
        cs = Request.changeset(%{})
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :amount)
        assert Keyword.has_key?(cs.errors, :currency)
        assert Keyword.has_key?(cs.errors, :customer_id)
      end
    end
    """
  end

  defp readme_content do
    """
    # Payment Gateway Mock

    Simula criação de cobrança e retorna um charge_id determinístico para testes
    de fluxos de pagamento sem conectar a um processador real.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `amount` | number | sim | Valor em centavos (ex: 2990 = R$29,90) |
    | `currency` | string | sim | Moeda em formato ISO 4217 (ex: `BRL`, `USD`) |
    | `customer_id` | string | sim | ID do cliente no sistema |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/payment-gateway \\
      -H "Content-Type: application/json" \\
      -d '{
        "amount": 2990,
        "currency": "BRL",
        "customer_id": "cus_mock_abc123"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "charge_id": "ch_mock_a1b2c3d4",
      "status": "succeeded",
      "amount": 2990,
      "currency": "BRL",
      "created_at": "2024-01-15T10:30:00Z"
    }
    ```

    ## Notas

    - O `charge_id` é determinístico: mesmo `customer_id` + `amount` geram o mesmo ID
    - Status sempre retorna `succeeded` (mock)
    - `amount` deve ser em centavos (inteiro)
    """
  end
end
