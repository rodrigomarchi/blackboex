defmodule Blackboex.FlowAgent.DefinitionPipeline do
  @moduledoc """
  Orchestrates a single LLM call for the FlowAgent: builds prompts, streams
  tokens through the `StreamManager`, parses the response with
  `DefinitionParser`, auto-fills any missing node positions via `AutoLayout`,
  and finally validates the resulting definition through the canonical
  `BlackboexFlow` validator.

  Returns `{:ok, %{definition, summary, input_tokens, output_tokens}}` on
  success or `{:error, reason}` on any failure.
  """

  require Logger

  alias Blackboex.FlowAgent.AutoLayout
  alias Blackboex.FlowAgent.DefinitionParser
  alias Blackboex.FlowAgent.Prompts
  alias Blackboex.FlowAgent.StreamManager
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.LLM.Config

  @type run_type :: :generate | :edit

  @type edit_result :: %{
          kind: :edit,
          definition: map(),
          summary: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type explain_result :: %{
          kind: :explain,
          answer: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type result :: edit_result() | explain_result()

  @type opts :: [
          run_id: String.t() | nil,
          token_callback: (String.t() -> :ok) | nil,
          client: module() | nil,
          history: [%{role: String.t(), content: String.t()}] | nil
        ]

  @spec run(run_type(), String.t(), map() | nil, opts()) ::
          {:ok, result()}
          | {:error,
             :no_content
             | {:invalid_json, term()}
             | {:invalid_flow, String.t()}
             | String.t()
             | term()}
  def run(run_type, message, definition_before, opts \\ [])
      when run_type in [:generate, :edit] do
    client = opts[:client] || Config.client()
    token_callback = opts[:token_callback]
    run_id = opts[:run_id]
    history = opts[:history] || []

    system = Prompts.system_prompt(run_type)
    prompt = Prompts.user_message(run_type, message, definition_before, history: history)

    with {:ok, %{content: content, usage: usage}} <-
           call_llm(client, prompt, system, token_callback),
         :ok <- maybe_flush(run_id) do
      interpret_response(content, usage)
    end
  end

  defp interpret_response(content, usage) do
    case DefinitionParser.classify(content) do
      {:edit, definition, summary} ->
        laid_out = AutoLayout.apply(definition)

        case validate_flow(laid_out) do
          :ok -> {:ok, build_edit_result(laid_out, summary, usage)}
          {:error, reason} -> {:error, reason}
        end

      {:explain, answer} ->
        {:ok, build_explain_result(answer, usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── LLM invocation ───────────────────────────────────────────────

  defp call_llm(client, prompt, system, nil) do
    case client.generate_text(prompt, system: system) do
      {:ok, %{content: _} = result} ->
        {:ok, %{content: result.content, usage: result[:usage] || %{}}}

      {:ok, content} when is_binary(content) ->
        {:ok, %{content: content, usage: %{}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, prompt, system, token_callback) when is_function(token_callback, 1) do
    case client.stream_text(prompt, system: system) do
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
      Logger.debug("FlowAgent stream failed, falling back to sync: #{Exception.message(e)}")
      call_llm(client, prompt, system, nil)
  end

  defp maybe_flush(nil), do: :ok

  defp maybe_flush(run_id) when is_binary(run_id) do
    StreamManager.flush_remaining(run_id)
    :ok
  end

  defp validate_flow(definition) do
    case BlackboexFlow.validate(definition) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_flow, reason}}
    end
  end

  defp build_edit_result(definition, summary, usage) do
    %{
      kind: :edit,
      definition: definition,
      summary: summary,
      input_tokens: Map.get(usage, :input_tokens, 0) || 0,
      output_tokens: Map.get(usage, :output_tokens, 0) || 0
    }
  end

  defp build_explain_result(answer, usage) do
    %{
      kind: :explain,
      answer: answer,
      input_tokens: Map.get(usage, :input_tokens, 0) || 0,
      output_tokens: Map.get(usage, :output_tokens, 0) || 0
    }
  end
end
