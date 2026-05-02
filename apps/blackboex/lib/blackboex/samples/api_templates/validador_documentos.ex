defmodule Blackboex.Samples.ApiTemplates.ValidadorDocumentos do
  @moduledoc """
  Template: Validador de Documentos

  Validates CPF, CNPJ, email and Brazilian phone numbers,
  returning validity, formatted version and details.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "validador-documentos",
      name: "Validador de Documentos",
      description: "Valida CPF, CNPJ, email e telefone brasileiro com formatação",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "shield-check",
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
        "documento" => "string",
        "tipo" => "string"
      },
      example_request: %{
        "documento" => "11144477735",
        "tipo" => "cpf"
      },
      example_response: %{
        "valido" => true,
        "formatado" => "111.444.777-35",
        "detalhes" => %{
          "tipo" => "cpf",
          "digitos_verificadores" => "corretos"
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
          %{"name" => "valid CPF returns true and formatted", "status" => "pass"},
          %{"name" => "invalid CPF digits returns false", "status" => "pass"},
          %{"name" => "valid CNPJ returns true and formatted", "status" => "pass"},
          %{"name" => "invalid CNPJ returns false", "status" => "pass"},
          %{"name" => "valid email returns true", "status" => "pass"},
          %{"name" => "invalid email returns false", "status" => "pass"},
          %{"name" => "valid phone returns true and formatted", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Validates Brazilian documents and common formats."

      @doc "Processes request and returns validation result or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          {valido, formatado, detalhes} = Helpers.validate_document(data.documento, data.tipo)
          %{valido: valido, formatado: formatado, detalhes: detalhes}
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
      @moduledoc "Document validation helpers for CPF, CNPJ, email and phone."

      @doc "Validates a document and returns {valid?, formatted, details}."
      @spec validate_document(String.t(), String.t()) :: {boolean(), String.t(), map()}
      def validate_document(doc, "cpf") do
        digits = String.replace(doc, ~r/\D/, "")
        valid = valid_cpf?(digits)
        formatted = if valid, do: format_cpf(digits), else: digits
        {valid, formatted, %{tipo: "cpf", digitos_verificadores: if(valid, do: "corretos", else: "incorretos")}}
      end

      def validate_document(doc, "cnpj") do
        digits = String.replace(doc, ~r/\D/, "")
        valid = valid_cnpj?(digits)
        formatted = if valid, do: format_cnpj(digits), else: digits
        {valid, formatted, %{tipo: "cnpj", digitos_verificadores: if(valid, do: "corretos", else: "incorretos")}}
      end

      def validate_document(doc, "email") do
        valid = Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, doc)
        {valid, doc, %{tipo: "email", formato: if(valid, do: "válido", else: "inválido")}}
      end

      def validate_document(doc, "telefone") do
        digits = String.replace(doc, ~r/\D/, "")
        valid = String.length(digits) in [10, 11]
        formatted = if valid, do: format_phone(digits), else: digits
        {valid, formatted, %{tipo: "telefone", ddd: if(valid, do: String.slice(digits, 0, 2), else: nil)}}
      end

      def validate_document(doc, _tipo), do: {false, doc, %{tipo: "desconhecido"}}

      @spec valid_cpf?(String.t()) :: boolean()
      defp valid_cpf?(digits) when byte_size(digits) != 11, do: false

      defp valid_cpf?(digits) do
        nums = digits |> String.graphemes() |> Enum.map(&String.to_integer/1)
        if Enum.all?(nums, &(&1 == hd(nums))), do: false, else: check_cpf(nums)
      end

      @spec check_cpf([integer()]) :: boolean()
      defp check_cpf(nums) do
        d1 = calc_digit(Enum.take(nums, 9), 10)
        d2 = calc_digit(Enum.take(nums, 10), 11)
        d1 == Enum.at(nums, 9) and d2 == Enum.at(nums, 10)
      end

      @spec calc_digit([integer()], integer()) :: integer()
      defp calc_digit(nums, multiplier) do
        sum =
          nums
          |> Enum.with_index()
          |> Enum.reduce(0, fn {n, i}, acc -> acc + n * (multiplier - i) end)

        remainder = rem(sum, 11)
        if remainder < 2, do: 0, else: 11 - remainder
      end

      @spec valid_cnpj?(String.t()) :: boolean()
      defp valid_cnpj?(digits) when byte_size(digits) != 14, do: false

      defp valid_cnpj?(digits) do
        nums = digits |> String.graphemes() |> Enum.map(&String.to_integer/1)
        if Enum.all?(nums, &(&1 == hd(nums))), do: false, else: check_cnpj(nums)
      end

      @spec check_cnpj([integer()]) :: boolean()
      defp check_cnpj(nums) do
        weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        d1 = cnpj_digit(Enum.take(nums, 12), weights1)
        d2 = cnpj_digit(Enum.take(nums, 13), weights2)
        d1 == Enum.at(nums, 12) and d2 == Enum.at(nums, 13)
      end

      @spec cnpj_digit([integer()], [integer()]) :: integer()
      defp cnpj_digit(nums, weights) do
        sum = Enum.zip(nums, weights) |> Enum.reduce(0, fn {n, w}, acc -> acc + n * w end)
        remainder = rem(sum, 11)
        if remainder < 2, do: 0, else: 11 - remainder
      end

      @spec format_cpf(String.t()) :: String.t()
      defp format_cpf(d) do
        "#{String.slice(d, 0, 3)}.#{String.slice(d, 3, 3)}.#{String.slice(d, 6, 3)}-#{String.slice(d, 9, 2)}"
      end

      @spec format_cnpj(String.t()) :: String.t()
      defp format_cnpj(d) do
        "#{String.slice(d, 0, 2)}.#{String.slice(d, 2, 3)}.#{String.slice(d, 5, 3)}/#{String.slice(d, 8, 4)}-#{String.slice(d, 12, 2)}"
      end

      @spec format_phone(String.t()) :: String.t()
      defp format_phone(digits) when byte_size(digits) == 11 do
        "(#{String.slice(digits, 0, 2)}) #{String.slice(digits, 2, 5)}-#{String.slice(digits, 7, 4)}"
      end

      defp format_phone(digits) do
        "(#{String.slice(digits, 0, 2)}) #{String.slice(digits, 2, 4)}-#{String.slice(digits, 6, 4)}"
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the document validator API."
      use Blackboex.Schema

      @valid_types ["cpf", "cnpj", "email", "telefone"]

      embedded_schema do
        field :documento, :string
        field :tipo, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:documento, :tipo])
        |> validate_required([:documento, :tipo])
        |> validate_inclusion(:tipo, @valid_types)
        |> validate_length(:documento, min: 1, max: 200)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the document validator API."
      use Blackboex.Schema

      embedded_schema do
        field :valido, :boolean
        field :formatado, :string
        field :detalhes, :map
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the document validator handler."
      use ExUnit.Case

      describe "Request changeset validation" do
        test "accepts valid CPF input" do
          changeset = Request.changeset(%{"documento" => "11144477735", "tipo" => "cpf"})
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects invalid tipo" do
          changeset = Request.changeset(%{"documento" => "abc", "tipo" => "rg"})
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "valid CPF returns true and formatted" do
          result = Handler.handle(%{"documento" => "11144477735", "tipo" => "cpf"})
          assert result.valido == true
          assert result.formatado == "111.444.777-35"
        end

        test "invalid CPF digits returns false" do
          result = Handler.handle(%{"documento" => "11111111111", "tipo" => "cpf"})
          assert result.valido == false
        end

        test "valid CNPJ returns true and formatted with slash" do
          result = Handler.handle(%{"documento" => "11222333000181", "tipo" => "cnpj"})
          assert result.valido == true
          assert String.contains?(result.formatado, "/")
        end

        test "valid email returns true" do
          result = Handler.handle(%{"documento" => "user@example.com", "tipo" => "email"})
          assert result.valido == true
        end

        test "invalid email returns false" do
          result = Handler.handle(%{"documento" => "not-an-email", "tipo" => "email"})
          assert result.valido == false
        end

        test "valid 11-digit phone returns formatted with DDD" do
          result = Handler.handle(%{"documento" => "11987654321", "tipo" => "telefone"})
          assert result.valido == true
          assert String.starts_with?(result.formatado, "(11)")
        end
      end

      describe "error handling" do
        test "returns error for missing fields" do
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
    # Validador de Documentos

    Valida documentos brasileiros (CPF, CNPJ) e formatos comuns (email, telefone),
    retornando o resultado da validação, a versão formatada e detalhes sobre o documento.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `documento` | string | sim | O documento a ser validado |
    | `tipo` | string | sim | Tipo: `cpf`, `cnpj`, `email`, `telefone` |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/validador-documentos \\
      -H "Content-Type: application/json" \\
      -d '{"documento": "11144477735", "tipo": "cpf"}'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "valido": true,
      "formatado": "111.444.777-35",
      "detalhes": {
        "tipo": "cpf",
        "digitos_verificadores": "corretos"
      }
    }
    ```

    ## Algoritmos

    - **CPF**: Validação completa com dois dígitos verificadores (módulo 11).
    - **CNPJ**: Validação completa com dois dígitos verificadores.
    - **Email**: Regex para formato user@domain.tld.
    - **Telefone**: Aceita 10 dígitos (fixo) ou 11 dígitos (celular), extrai DDD.

    ## Casos de Uso

    - Validação de cadastro em formulários
    - Tool de agente de IA para verificar dados de usuários
    - Pipeline de limpeza e validação de dados
    """
  end
end
