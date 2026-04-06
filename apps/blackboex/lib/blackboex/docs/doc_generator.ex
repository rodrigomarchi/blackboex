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

  @spec generate(Api.t(), keyword()) :: {:ok, %{doc: String.t(), usage: map()}} | {:error, term()}
  def generate(%Api{} = api, opts \\ []) do
    openapi_spec = OpenApiGenerator.generate(api, opts)
    prompt = DocPrompts.build_doc_prompt(api, openapi_spec)
    system = DocPrompts.system_prompt()
    client = Keyword.get_lazy(opts, :client, &Config.client/0)
    token_callback = Keyword.get(opts, :token_callback)

    if token_callback do
      generate_streaming(client, prompt, system, token_callback)
    else
      generate_batch(client, prompt, system)
    end
  end

  defp generate_batch(client, prompt, system) do
    case client.generate_text(prompt, system: system) do
      {:ok, %{content: content} = response} ->
        {:ok, %{doc: String.trim(content), usage: Map.get(response, :usage, %{})}}

      {:error, reason} ->
        Logger.debug("Doc generation failed: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end

  defp generate_streaming(client, prompt, system, token_callback) do
    case client.stream_text(prompt, system: system) do
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
