defmodule Blackboex.PageAgent.ContentPipeline do
  @moduledoc """
  Markdown-content pipeline for the Page AI agent.

  Makes exactly ONE LLM call per run. Streams tokens through the given
  callback and returns the extracted markdown content plus a short summary.
  Unlike the playground pipeline, nothing is executed — the output is just
  prose that will be applied to the page's `content` field.
  """

  require Logger

  alias Blackboex.LLM.Config
  alias Blackboex.PageAgent.ContentParser
  alias Blackboex.PageAgent.Prompts
  alias Blackboex.PageAgent.StreamManager

  @type run_type :: :generate | :edit

  @type result :: %{
          content: String.t(),
          summary: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type opts :: [
          run_id: String.t() | nil,
          token_callback: (String.t() -> :ok) | nil,
          client: module() | nil,
          history: [%{role: String.t(), content: String.t()}] | nil,
          project_id: Ecto.UUID.t() | nil,
          api_key: String.t() | nil
        ]

  @spec run(run_type(), String.t(), String.t() | nil, opts()) ::
          {:ok, result()} | {:error, :not_configured | String.t()}
  def run(run_type, message, content_before, opts \\ [])
      when run_type in [:generate, :edit] do
    token_callback = opts[:token_callback]
    run_id = opts[:run_id]
    history = opts[:history] || []

    system = Prompts.system_prompt(run_type)
    prompt = Prompts.user_message(run_type, message, content_before, history: history)

    with {:ok, client, llm_opts} <- Config.resolve_client(opts),
         {:ok, %{content: body, usage: usage}} <-
           call_llm(client, prompt, system, token_callback, llm_opts),
         :ok <- maybe_flush(run_id),
         {:ok, content} <- ContentParser.extract_content(body) do
      summary = ContentParser.extract_summary(body)
      {:ok, build_result(content, summary, usage)}
    else
      {:error, :not_configured} ->
        {:error, :not_configured}

      {:error, :no_content_block} ->
        {:error, "resposta do modelo não continha bloco markdown"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "falha do LLM: #{inspect(reason)}"}
    end
  end

  defp call_llm(client, prompt, system, nil, llm_opts) do
    case client.generate_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %{content: _} = result} ->
        {:ok, %{content: result.content, usage: result[:usage] || %{}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, prompt, system, token_callback, llm_opts)
       when is_function(token_callback, 1) do
    case client.stream_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        content =
          response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            token_callback.(token)
            acc <> token
          end)

        usage = ReqLLM.StreamResponse.usage(response) || %{}
        {:ok, %{content: content, usage: usage}}

      {:ok, stream} ->
        content =
          Enum.reduce(stream, "", fn
            {:token, token}, acc ->
              token_callback.(token)
              acc <> token

            token, acc when is_binary(token) ->
              token_callback.(token)
              acc <> token
          end)

        {:ok, %{content: content, usage: %{}}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e in [RuntimeError, Protocol.UndefinedError, ArgumentError] ->
      Logger.warning("Page stream failed, falling back to sync: #{Exception.message(e)}")
      call_llm(client, prompt, system, nil, llm_opts)
  end

  defp maybe_flush(nil), do: :ok

  defp maybe_flush(run_id) when is_binary(run_id) do
    StreamManager.flush_remaining(run_id)
    :ok
  end

  defp build_result(content, summary, usage) do
    %{
      content: content,
      summary: summary,
      input_tokens: Map.get(usage, :input_tokens, 0) || 0,
      output_tokens: Map.get(usage, :output_tokens, 0) || 0
    }
  end
end
