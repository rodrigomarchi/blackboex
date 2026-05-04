defmodule Blackboex.Samples.ApiTemplates.FormSubmission do
  @moduledoc """
  Template: Form Submission Backend

  Receives contact form and lead capture data, validates all fields,
  and returns a submission confirmation with a unique ID.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "form-submission",
      name: "Form Submission Backend",
      description: "Receives contact form and lead data with complete validation",
      category: "Webhooks",
      template_type: "computation",
      icon: "file-text",
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
        "name" => "string",
        "email" => "string",
        "phone" => "string",
        "message" => "string"
      },
      example_request: %{
        "name" => "Mary Smith",
        "email" => "mary@example.com",
        "phone" => "+5511999999999",
        "message" => "I would like more information about the product."
      },
      example_response: %{
        "success" => true,
        "submission_id" => "sub_a1b2c3d4",
        "message" => "Thanks for reaching out. We will reply within 24 hours."
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
          %{"name" => "valid form submission returns confirmation", "status" => "pass"},
          %{"name" => "missing name returns error", "status" => "pass"},
          %{"name" => "missing email returns error", "status" => "pass"},
          %{"name" => "invalid email format returns error", "status" => "pass"},
          %{"name" => "missing message returns error", "status" => "pass"},
          %{"name" => "message too short returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Form Submission Backend handler."

      @doc "Processes a form submission and returns a confirmation map."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          submission_id = Helpers.generate_submission_id()

          %{
            success: true,
            submission_id: submission_id,
            message: "Thanks for reaching out. We will reply within 24 hours."
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
      @moduledoc "Helper functions for Form Submission handler."

      @prefix "sub_"

      @doc "Generates a unique submission ID with a 'sub_' prefix."
      @spec generate_submission_id() :: String.t()
      def generate_submission_id do
        random = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        "#{@prefix}#{random}"
      end

      @doc "Returns true if the email matches a basic valid format."
      @spec valid_email?(String.t()) :: boolean()
      def valid_email?(email) do
        Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email)
      end

      @doc "Strips whitespace, dashes, and parentheses from a phone string."
      @spec sanitize_phone(String.t() | nil) :: String.t() | nil
      def sanitize_phone(nil), do: nil

      def sanitize_phone(phone) do
        phone
        |> String.replace(~r/[\s\-\(\)]/, "")
        |> String.slice(0, 20)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for Form Submission handler."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :name, :string
        field :email, :string
        field :phone, :string
        field :message, :string
      end

      @doc "Casts and validates form submission params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:name, :email, :phone, :message])
        |> validate_required([:name, :email, :message])
        |> validate_length(:name, min: 2, max: 200)
        |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
          message: "must be a valid email address"
        )
        |> validate_length(:email, max: 500)
        |> validate_length(:message, min: 10, max: 5000)
        |> validate_length(:phone, max: 30)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema for Form Submission handler — documents output structure."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :success, :boolean
        field :submission_id, :string
        field :message, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case

      @valid_params %{
        "name" => "Mary Smith",
        "email" => "mary@example.com",
        "phone" => "+5511999999999",
        "message" => "I would like more information about the product."
      }

      test "valid form submission returns confirmation" do
        result = Handler.handle(@valid_params)
        assert result.success == true
        assert is_binary(result.submission_id)
        assert String.starts_with?(result.submission_id, "sub_")
        assert is_binary(result.message)
      end

      test "missing name returns error" do
        params = Map.delete(@valid_params, "name")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :name)
      end

      test "missing email returns error" do
        params = Map.delete(@valid_params, "email")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :email)
      end

      test "invalid email format returns error" do
        params = Map.put(@valid_params, "email", "not-an-email")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :email)
      end

      test "missing message returns error" do
        params = Map.delete(@valid_params, "message")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :message)
      end

      test "message too short returns error" do
        params = Map.put(@valid_params, "message", "Hi")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :message)
      end

      test "Request.changeset/1 is valid with required fields" do
        cs = Request.changeset(@valid_params)
        assert cs.valid?
      end

      test "Request.changeset/1 is invalid when email is missing" do
        cs = Request.changeset(Map.delete(@valid_params, "email"))
        refute cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # Form Submission Backend

    Receives contact form and lead capture data, validates all fields and
    returns a confirmation with a unique submission ID.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `name` | string | yes | Full name (2-200 characters) |
    | `email` | string | yes | Valid email address |
    | `message` | string | yes | Message (minimum 10 characters) |
    | `phone` | string | no | Phone number (free-form, max 30 characters) |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/form-submission \\
      -H "Content-Type: application/json" \\
      -d '{
        "name": "Mary Smith",
        "email": "mary@example.com",
        "phone": "+5511999999999",
        "message": "I would like more information about the product."
      }'
    ```

    ## Example Response

    ```json
    {
      "success": true,
      "submission_id": "sub_a1b2c3d4",
      "message": "Thanks for reaching out. We will reply within 24 hours."
    }
    ```

    ## Validations

    - `name`: required, 2-200 characters
    - `email`: required, valid format (`user@domain.tld`)
    - `message`: required, minimum 10 characters, maximum 5000
    - `phone`: optional, maximum 30 characters

    ## Use Cases

    - Landing page contact form
    - Lead capture with server-side validation
    - Integration with CRM tools through webhook
    """
  end
end
