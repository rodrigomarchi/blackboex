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

  @doc "Generate tests for raw source code with a template type string."
  @spec generate_tests_for_code(String.t(), String.t(), keyword()) ::
          {:ok, %{code: String.t(), usage: map()}}
          | {:error, :generation_failed | :compile_error | :no_code_found}
  def generate_tests_for_code(source_code, template_type, opts \\ [])
      when is_binary(source_code) and is_binary(template_type) do
    api = %Api{
      id: Ecto.UUID.generate(),
      project_id: Keyword.get(opts, :project_id),
      name: "GeneratedAPI",
      slug: "generated-api",
      description: "Auto-generated API for test generation",
      template_type: template_type,
      method: "POST",
      requires_auth: false,
      organization_id: Ecto.UUID.generate(),
      user_id: 0
    }

    generate_tests(api, Keyword.put(opts, :source_code, source_code))
  end

  @doc "Generate tests for an API struct using the LLM."
  @spec generate_tests(Api.t(), keyword()) ::
          {:ok, %{code: String.t(), usage: map()}}
          | {:error, :generation_failed | :compile_error | :no_code_found | :not_configured}
  def generate_tests(%Api{} = api, opts \\ []) do
    openapi_spec = OpenApiGenerator.generate(api, opts)
    source_code = Keyword.get(opts, :source_code)
    prompt = TestPrompts.build_generation_prompt(api, openapi_spec, source_code)
    system = TestPrompts.system_prompt()

    with {:ok, client, llm_opts} <- resolve_client(api, opts),
         {:ok, response, usage} <- call_llm_and_normalize(client, prompt, system, opts, llm_opts),
         {:ok, code} <- TestPrompts.parse_response(response) do
      validate_with_retry(code, system, client, llm_opts, opts, 0, usage)
    end
  end

  defp call_llm_and_normalize(client, prompt, system, opts, llm_opts) do
    case call_llm(client, prompt, system, opts, llm_opts) do
      {:ok, response, usage} -> {:ok, response, usage}
      {:error, _reason} -> {:error, :generation_failed}
    end
  end

  # Merges the API's `project_id` into opts so the shared
  # `Config.resolve_client/1` helper can resolve the project-scoped key.
  # Explicit `:client` / `:api_key` in opts still take precedence.
  defp resolve_client(%Api{project_id: project_id}, opts) do
    merged =
      if is_binary(project_id) and is_nil(opts[:project_id]) do
        Keyword.put(opts, :project_id, project_id)
      else
        opts
      end

    Config.resolve_client(merged)
  end

  defp validate_with_retry(_code, _system, _client, _llm_opts, _opts, attempt, _usage)
       when attempt >= @max_retries do
    Logger.debug("Test generation failed after #{@max_retries} retry attempts")
    {:error, :compile_error}
  end

  defp validate_with_retry(code, system, client, llm_opts, opts, attempt, usage) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        {:ok, %{code: code, usage: usage}}

      {:error, {_meta, message, token}} ->
        error_msg = "#{message}#{token}"

        Logger.info(
          "Test code compile error (attempt #{attempt + 1}/#{@max_retries}): #{error_msg}"
        )

        retry_prompt = TestPrompts.build_retry_prompt(code, error_msg)
        retry_from_llm(retry_prompt, system, client, llm_opts, opts, attempt, usage)
    end
  end

  defp retry_from_llm(retry_prompt, system, client, llm_opts, opts, attempt, prev_usage) do
    case call_llm(client, retry_prompt, system, opts, llm_opts) do
      {:ok, response, usage} ->
        merged = merge_usage(prev_usage, usage)
        handle_retry_response(response, system, client, llm_opts, opts, attempt, merged)

      {:error, _reason} ->
        {:error, :generation_failed}
    end
  end

  defp handle_retry_response(response, system, client, llm_opts, opts, attempt, usage) do
    case TestPrompts.parse_response(response) do
      {:ok, fixed_code} ->
        validate_with_retry(fixed_code, system, client, llm_opts, opts, attempt + 1, usage)

      {:error, :no_code_found} ->
        {:error, :compile_error}
    end
  end

  defp call_llm(client, prompt, system, opts, llm_opts) do
    token_callback = Keyword.get(opts, :token_callback)

    if token_callback do
      call_llm_streaming(client, prompt, system, token_callback, llm_opts)
    else
      case client.generate_text(prompt, Keyword.merge(llm_opts, system: system)) do
        {:ok, %{content: content} = response} ->
          {:ok, content, Map.get(response, :usage, %{})}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp call_llm_streaming(client, prompt, system, token_callback, llm_opts) do
    case client.stream_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        full =
          response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            token_callback.(token)
            acc <> token
          end)

        {:ok, full, %{}}

      {:ok, stream} ->
        full =
          Enum.reduce(stream, "", fn {:token, token}, acc ->
            token_callback.(token)
            acc <> token
          end)

        {:ok, full, %{}}

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
