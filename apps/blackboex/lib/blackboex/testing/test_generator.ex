defmodule Blackboex.Testing.TestGenerator do
  @moduledoc """
  Generates ExUnit test code for an API using the LLM.
  Includes retry loop: if generated code doesn't compile, errors
  are sent back to the LLM for correction (up to 3 retries).
  """

  require Logger

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.OpenApiGenerator
  alias Blackboex.LLM.Config
  alias Blackboex.Testing.TestPrompts

  @max_retries 3

  @spec generate_tests(Api.t(), keyword()) ::
          {:ok, %{code: String.t(), usage: map()}}
          | {:error, :generation_failed | :compile_error | :no_code_found}
  def generate_tests(%Api{} = api, opts \\ []) do
    openapi_spec = OpenApiGenerator.generate(api, opts)
    prompt = TestPrompts.build_generation_prompt(api, openapi_spec)
    system = TestPrompts.system_prompt()

    case call_llm(prompt, system, opts) do
      {:ok, response, usage} ->
        case TestPrompts.parse_response(response) do
          {:ok, code} -> validate_with_retry(code, system, opts, 0, usage)
          {:error, :no_code_found} -> {:error, :no_code_found}
        end

      {:error, _reason} ->
        {:error, :generation_failed}
    end
  end

  defp validate_with_retry(_code, _system, _opts, attempt, _usage) when attempt >= @max_retries do
    Logger.warning("Test generation failed after #{@max_retries} retry attempts")
    {:error, :compile_error}
  end

  defp validate_with_retry(code, system, opts, attempt, usage) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        {:ok, %{code: code, usage: usage}}

      {:error, {_meta, message, token}} ->
        error_msg = "#{message}#{token}"

        Logger.info(
          "Test code compile error (attempt #{attempt + 1}/#{@max_retries}): #{error_msg}"
        )

        retry_prompt = TestPrompts.build_retry_prompt(code, error_msg)
        retry_from_llm(retry_prompt, system, opts, attempt, usage)
    end
  end

  defp retry_from_llm(retry_prompt, system, opts, attempt, prev_usage) do
    case call_llm(retry_prompt, system, opts) do
      {:ok, response, usage} ->
        merged = merge_usage(prev_usage, usage)
        handle_retry_response(response, system, opts, attempt, merged)

      {:error, _reason} ->
        {:error, :generation_failed}
    end
  end

  defp handle_retry_response(response, system, opts, attempt, usage) do
    case TestPrompts.parse_response(response) do
      {:ok, fixed_code} -> validate_with_retry(fixed_code, system, opts, attempt + 1, usage)
      {:error, :no_code_found} -> {:error, :compile_error}
    end
  end

  defp call_llm(prompt, system, opts) do
    client = Keyword.get_lazy(opts, :client, &Config.client/0)

    case client.generate_text(prompt, system: system) do
      {:ok, %{content: content} = response} ->
        {:ok, content, Map.get(response, :usage, %{})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp merge_usage(prev, new) do
    %{
      input_tokens: Map.get(prev, :input_tokens, 0) + Map.get(new, :input_tokens, 0),
      output_tokens: Map.get(prev, :output_tokens, 0) + Map.get(new, :output_tokens, 0)
    }
  end
end
