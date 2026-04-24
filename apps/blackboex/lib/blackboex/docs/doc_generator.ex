defmodule Blackboex.Docs.DocGenerator do
  @moduledoc """
  Generates Markdown documentation for an API using the LLM.
  Supports both batch and streaming modes.
  """

  require Logger

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.DocPrompts
  alias Blackboex.Docs.OpenApiGenerator
  alias Blackboex.LLM.Config

  @spec generate(Api.t(), keyword()) ::
          {:ok, %{doc: String.t(), usage: map()}}
          | {:error, :generation_failed | :not_configured}
  def generate(%Api{} = api, opts \\ []) do
    openapi_spec = OpenApiGenerator.generate(api, opts)
    source_code = Keyword.get(opts, :source_code)
    prompt = DocPrompts.build_doc_prompt(api, openapi_spec, source_code)
    system = DocPrompts.system_prompt()
    token_callback = Keyword.get(opts, :token_callback)

    with {:ok, client, llm_opts} <- resolve_client(api, opts) do
      if token_callback do
        generate_streaming(client, prompt, system, token_callback, llm_opts)
      else
        generate_batch(client, prompt, system, llm_opts)
      end
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

  defp generate_batch(client, prompt, system, llm_opts) do
    case client.generate_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %{content: content} = response} ->
        {:ok, %{doc: String.trim(content), usage: Map.get(response, :usage, %{})}}

      {:error, reason} ->
        Logger.debug("Doc generation failed: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end

  defp generate_streaming(client, prompt, system, token_callback, llm_opts) do
    case client.stream_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        full =
          response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            token_callback.(token)
            acc <> token
          end)

        {:ok, %{doc: String.trim(full), usage: %{}}}

      {:ok, stream} ->
        full =
          Enum.reduce(stream, "", fn {:token, token}, acc ->
            token_callback.(token)
            acc <> token
          end)

        {:ok, %{doc: String.trim(full), usage: %{}}}

      {:error, reason} ->
        Logger.debug("Doc generation streaming failed: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end
end
