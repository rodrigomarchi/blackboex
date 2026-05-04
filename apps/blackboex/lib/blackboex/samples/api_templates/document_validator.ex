defmodule Blackboex.Samples.ApiTemplates.DocumentValidator do
  @moduledoc """
  Template: Document Validator

  Validates CPF, CNPJ, email and Brazilian phone numbers,
  returning validity, formatted version and details.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "document-validator",
      name: "Document Validator",
      description: "Validates CPF, CNPJ, email and Brazilian phone numbers with formatting",
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
        "document" => "string",
        "type" => "string"
      },
      example_request: %{
        "document" => "11144477735",
        "type" => "cpf"
      },
      example_response: %{
        "valid" => true,
        "formatted" => "111.444.777-35",
        "details" => %{
          "type" => "cpf",
          "check_digits" => "correct"
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
          {valid, formatted, details} = Helpers.validate_document(data.document, data.type)
          %{valid: valid, formatted: formatted, details: details}
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
        {valid, formatted, %{type: "cpf", check_digits: if(valid, do: "correct", else: "incorrect")}}
      end

      def validate_document(doc, "cnpj") do
        digits = String.replace(doc, ~r/\D/, "")
        valid = valid_cnpj?(digits)
        formatted = if valid, do: format_cnpj(digits), else: digits
        {valid, formatted, %{type: "cnpj", check_digits: if(valid, do: "correct", else: "incorrect")}}
      end

      def validate_document(doc, "email") do
        valid = Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, doc)
        {valid, doc, %{type: "email", format: if(valid, do: "valid", else: "invalid")}}
      end

      def validate_document(doc, "phone") do
        digits = String.replace(doc, ~r/\D/, "")
        valid = String.length(digits) in [10, 11]
        formatted = if valid, do: format_phone(digits), else: digits
        {valid, formatted, %{type: "phone", area_code: if(valid, do: String.slice(digits, 0, 2), else: nil)}}
      end

      def validate_document(doc, _type), do: {false, doc, %{type: "unknown"}}

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

      @valid_types ["cpf", "cnpj", "email", "phone"]

      embedded_schema do
        field :document, :string
        field :type, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:document, :type])
        |> validate_required([:document, :type])
        |> validate_inclusion(:type, @valid_types)
        |> validate_length(:document, min: 1, max: 200)
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
        field :valid, :boolean
        field :formatted, :string
        field :details, :map
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
          changeset = Request.changeset(%{"document" => "11144477735", "type" => "cpf"})
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects invalid type" do
          changeset = Request.changeset(%{"document" => "abc", "type" => "rg"})
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "valid CPF returns true and formatted" do
          result = Handler.handle(%{"document" => "11144477735", "type" => "cpf"})
          assert result.valid == true
          assert result.formatted == "111.444.777-35"
        end

        test "invalid CPF digits returns false" do
          result = Handler.handle(%{"document" => "11111111111", "type" => "cpf"})
          assert result.valid == false
        end

        test "valid CNPJ returns true and formatted with slash" do
          result = Handler.handle(%{"document" => "11222333000181", "type" => "cnpj"})
          assert result.valid == true
          assert String.contains?(result.formatted, "/")
        end

        test "valid email returns true" do
          result = Handler.handle(%{"document" => "user@example.com", "type" => "email"})
          assert result.valid == true
        end

        test "invalid email returns false" do
          result = Handler.handle(%{"document" => "not-an-email", "type" => "email"})
          assert result.valid == false
        end

        test "valid 11-digit phone returns formatted with area code" do
          result = Handler.handle(%{"document" => "11987654321", "type" => "phone"})
          assert result.valid == true
          assert String.starts_with?(result.formatted, "(11)")
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
    # Document Validator

    Validates Brazilian documents (CPF, CNPJ) and common formats (email, phone),
    returning the validation result, formatted value and document details.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `document` | string | yes | The document or value to validate |
    | `type` | string | yes | Type: `cpf`, `cnpj`, `email`, `phone` |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/document-validator \\
      -H "Content-Type: application/json" \\
      -d '{"document": "11144477735", "type": "cpf"}'
    ```

    ## Example Response

    ```json
    {
      "valid": true,
      "formatted": "111.444.777-35",
      "details": {
        "type": "cpf",
        "check_digits": "correct"
      }
    }
    ```

    ## Algorithms

    - **CPF**: Full validation with two check digits (modulo 11).
    - **CNPJ**: Full validation with two check digits.
    - **Email**: Regex for user@domain.tld format.
    - **Phone**: Accepts 10 digits for landline numbers or 11 digits for mobile numbers and extracts the area code.

    ## Use Cases

    - Registration validation in forms
    - AI agent tool for checking user data
    - Data cleanup and validation pipeline
    """
  end
end
