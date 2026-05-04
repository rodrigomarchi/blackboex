defmodule Blackboex.Samples.ApiTemplates.OpenaiStub do
  @moduledoc """
  Template: OpenAI-Compatible Stub

  Implements the /v1/chat/completions endpoint compatible with the OpenAI SDK.
  Returns hardcoded responses useful for testing AI integrations without API costs.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "openai-stub",
      name: "OpenAI-Compatible Stub",
      description: "OpenAI SDK-compatible /v1/chat/completions endpoint for tests",
      category: "Mocks",
      template_type: "computation",
      icon: "cpu",
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
        "model" => "string",
        "messages" => "array",
        "temperature" => "number",
        "max_tokens" => "number"
      },
      example_request: %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "Hello!"}
        ],
        "temperature" => 0.7,
        "max_tokens" => 150
      },
      example_response: %{
        "id" => "chatcmpl-stub123",
        "object" => "chat.completion",
        "created" => 1_697_123_456,
        "model" => "gpt-4",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! I'm a stub response. How can I help you today?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 20,
          "completion_tokens" => 15,
          "total_tokens" => 35
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
          %{"name" => "valid chat request returns OpenAI-format response", "status" => "pass"},
          %{"name" => "response has required OpenAI fields", "status" => "pass"},
          %{"name" => "missing messages returns validation error", "status" => "pass"},
          %{"name" => "missing model returns validation error", "status" => "pass"},
          %{"name" => "model name is echoed in response", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for OpenAI-compatible stub endpoint."

      @doc "Processes a chat completion request and returns a stub response."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          Helpers.build_completion(data)
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
      @moduledoc "Helper functions for building stub OpenAI responses."

      @stub_content "Hello! I'm a stub response. How can I help you today?"

      @doc "Builds a stub chat completion response map."
      @spec build_completion(map()) :: map()
      def build_completion(data) do
        model = data.model
        created = DateTime.utc_now() |> DateTime.to_unix()
        id = "chatcmpl-stub#{Integer.to_string(created, 16)}"

        %{
          id: id,
          object: "chat.completion",
          created: created,
          model: model,
          choices: [
            %{
              index: 0,
              message: %{role: "assistant", content: @stub_content},
              finish_reason: "stop"
            }
          ],
          usage: %{
            prompt_tokens: 20,
            completion_tokens: 15,
            total_tokens: 35
          }
        }
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for OpenAI-compatible stub."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :model, :string
        field :messages, {:array, :map}
        field :temperature, :float
        field :max_tokens, :integer
        field :stream, :boolean
      end

      @doc "Casts and validates request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:model, :messages, :temperature, :max_tokens, :stream])
        |> validate_required([:model, :messages])
        |> validate_length(:model, min: 1, max: 100)
        |> validate_length(:messages, min: 1)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the OpenAI-compatible stub output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :id, :string
        field :object, :string
        field :created, :integer
        field :model, :string
        field :choices, {:array, :map}
        field :usage, :map
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      @valid_params %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello!"}
        ],
        "temperature" => 0.7,
        "max_tokens" => 150
      }

      test "valid chat request returns OpenAI-format response" do
        result = Handler.handle(@valid_params)
        assert result.object == "chat.completion"
        assert is_binary(result.id)
        assert is_list(result.choices)
        assert length(result.choices) == 1
      end

      test "response has required OpenAI fields" do
        result = Handler.handle(@valid_params)
        assert Map.has_key?(result, :id)
        assert Map.has_key?(result, :object)
        assert Map.has_key?(result, :created)
        assert Map.has_key?(result, :model)
        assert Map.has_key?(result, :choices)
        assert Map.has_key?(result, :usage)
      end

      test "model name is echoed in response" do
        result = Handler.handle(@valid_params)
        assert result.model == "gpt-4"
      end

      test "missing messages returns validation error" do
        result = Handler.handle(Map.delete(@valid_params, "messages"))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :messages)
      end

      test "missing model returns validation error" do
        result = Handler.handle(Map.delete(@valid_params, "model"))
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :model)
      end

      test "Request.changeset validates required fields" do
        cs = Request.changeset(%{})
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :model)
        assert Keyword.has_key?(cs.errors, :messages)
      end
    end
    """
  end

  defp readme_content do
    """
    # OpenAI-Compatible Stub

    Implements the OpenAI SDK-compatible `/v1/chat/completions` endpoint.
    Returns hardcoded responses for testing AI integrations without API cost.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `model` | string | yes | Model name (for example: `gpt-4`, `gpt-3.5-turbo`) |
    | `messages` | array | yes | Message list with `{role, content}` |
    | `temperature` | number | no | Temperature (0.0-2.0) |
    | `max_tokens` | number | no | Maximum response tokens |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/openai-stub \\
      -H "Content-Type: application/json" \\
      -H "Authorization: Bearer any-token" \\
      -d '{
        "model": "gpt-4",
        "messages": [
          {"role": "system", "content": "You are a helpful assistant."},
          {"role": "user", "content": "Hello!"}
        ]
      }'
    ```

    ## Example Response

    ```json
    {
      "id": "chatcmpl-stub123",
      "object": "chat.completion",
      "created": 1697123456,
      "model": "gpt-4",
      "choices": [{
        "index": 0,
        "message": {"role": "assistant", "content": "Hello! I'm a stub response."},
        "finish_reason": "stop"
      }],
      "usage": {"prompt_tokens": 20, "completion_tokens": 15, "total_tokens": 35}
    }
    ```

    ## Use Cases

    - Test AI agent pipelines without cost
    - CI/CD without external API dependency
    - Offline development of LLM integrations
    """
  end
end
