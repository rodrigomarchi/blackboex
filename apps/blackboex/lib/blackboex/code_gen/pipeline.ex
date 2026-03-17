defmodule Blackboex.CodeGen.Pipeline do
  @moduledoc """
  Code generation pipeline. Classifies the API type, builds prompts,
  calls the LLM, and extracts code from the response.
  """

  alias Blackboex.CodeGen.GenerationResult
  alias Blackboex.LLM.{Config, Prompts}

  @crud_keywords ~w(crud store database banco armazenar listar persist persistir save salvar)
  @webhook_keywords ~w(webhook receive callback receber notificacao notificação)

  @spec generate(String.t(), keyword()) :: {:ok, GenerationResult.t()} | {:error, atom()}
  def generate(description, opts \\ []) do
    client = Config.client()
    provider = Config.default_provider()
    start_time = System.monotonic_time(:millisecond)

    template = classify_type(description)
    prompt = Prompts.build_generation_prompt(description, template)
    system = Prompts.system_prompt()

    case client.generate_text(prompt, Keyword.merge(opts, model: provider.model, system: system)) do
      {:ok, %{content: content, usage: usage}} ->
        case extract_code(content) do
          {:ok, code} ->
            duration_ms = System.monotonic_time(:millisecond) - start_time
            total_tokens = Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)

            {:ok,
             %GenerationResult{
               code: code,
               template: template,
               description: description,
               provider: to_string(provider.name),
               model: provider.model,
               tokens_used: total_tokens,
               duration_ms: duration_ms
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _reason} ->
        {:error, :llm_failed}
    end
  end

  @spec classify_type(String.t()) :: atom()
  def classify_type(description) do
    downcased = String.downcase(description)

    cond do
      Enum.any?(@crud_keywords, &String.contains?(downcased, &1)) -> :crud
      Enum.any?(@webhook_keywords, &String.contains?(downcased, &1)) -> :webhook
      true -> :computation
    end
  end

  @spec extract_code(String.t()) :: {:ok, String.t()} | {:error, :no_code_in_response}
  def extract_code(response) do
    case Regex.run(~r/```(?:elixir)?\n(.*?)```/s, response) do
      [_, code] -> {:ok, String.trim(code)}
      nil -> {:error, :no_code_in_response}
    end
  end
end
