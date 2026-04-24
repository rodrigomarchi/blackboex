defmodule Blackboex.PlaygroundAgent.CodePipeline do
  @moduledoc """
  Single-file Elixir code pipeline for the Playground AI agent.

  Makes exactly ONE LLM call per run (no validation/fix loops like the API
  pipeline — the Executor sandbox catches runtime errors at execution time).
  Streams tokens through the given callback and returns the extracted code
  plus a short summary.
  """

  require Logger

  alias Blackboex.LLM.Config
  alias Blackboex.PlaygroundAgent.CodeParser
  alias Blackboex.PlaygroundAgent.Prompts
  alias Blackboex.PlaygroundAgent.StreamManager

  @type run_type :: :generate | :edit

  @type result :: %{
          code: String.t(),
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
  def run(run_type, message, code_before, opts \\ []) when run_type in [:generate, :edit] do
    token_callback = opts[:token_callback]
    run_id = opts[:run_id]
    history = opts[:history] || []

    system = Prompts.system_prompt(run_type)
    prompt = Prompts.user_message(run_type, message, code_before, history: history)

    with {:ok, client, llm_opts} <- Config.resolve_client(opts),
         {:ok, %{content: content, usage: usage}} <-
           call_llm(client, prompt, system, token_callback, llm_opts),
         :ok <- maybe_flush(run_id),
         {:ok, code} <- CodeParser.extract_code(content) do
      summary = CodeParser.extract_summary(content)
      {:ok, build_result(code, summary, usage)}
    else
      {:error, :not_configured} ->
        {:error, :not_configured}

      {:error, :no_code_block} ->
        {:error, "resposta do modelo não continha bloco de código Elixir"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "falha do LLM: #{inspect(reason)}"}
    end
  end

  # ── LLM invocation ───────────────────────────────────────────────

  defp call_llm(client, prompt, system, nil, llm_opts) do
    case client.generate_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %{content: _content} = result} ->
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
    e ->
      Logger.debug("Playground stream failed, falling back to sync: #{Exception.message(e)}")
      call_llm(client, prompt, system, nil, llm_opts)
  end

  defp maybe_flush(nil), do: :ok

  defp maybe_flush(run_id) when is_binary(run_id) do
    StreamManager.flush_remaining(run_id)
    :ok
  end

  defp build_result(code, summary, usage) do
    %{
      code: code,
      summary: summary,
      input_tokens: Map.get(usage, :input_tokens, 0) || 0,
      output_tokens: Map.get(usage, :output_tokens, 0) || 0
    }
  end
end
