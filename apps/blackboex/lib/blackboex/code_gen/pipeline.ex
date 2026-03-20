defmodule Blackboex.CodeGen.Pipeline do
  @moduledoc """
  Code generation pipeline. Classifies the API type, builds prompts,
  calls the LLM, and extracts code from the response.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.GenerationResult
  alias Blackboex.LLM.{Config, Prompts}
  alias Blackboex.Organizations
  alias Blackboex.Telemetry.Events

  @crud_keywords ~w(crud store database banco armazenar listar persist persistir save salvar)
  @webhook_keywords ~w(webhook receive callback receber notificacao notificação)

  @spec generate(String.t(), keyword()) ::
          {:ok, GenerationResult.t()} | {:error, term()} | {:error, :limit_exceeded, map()}
  def generate(description, opts \\ []) do
    with :ok <- check_llm_limit(opts) do
      do_generate(description, opts)
    end
  end

  defp check_llm_limit(opts) do
    with {:ok, org_id} <- Keyword.fetch(opts, :organization_id),
         org when not is_nil(org) <- Organizations.get_organization(org_id) do
      case Enforcement.check_limit(org, :llm_generation) do
        {:ok, _remaining} -> :ok
        {:error, :limit_exceeded, details} -> {:error, :limit_exceeded, details}
      end
    else
      _ -> :ok
    end
  end

  defp do_generate(description, opts) do
    Tracer.with_span "blackboex.codegen.generate" do
      do_generate_inner(description, opts)
    end
  end

  defp do_generate_inner(description, opts) do
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

            Tracer.set_attributes([
              {"blackboex.template_type", to_string(template)},
              {"blackboex.description_length", String.length(description)},
              {"gen_ai.usage.input_tokens", Map.get(usage, :input_tokens, 0)},
              {"gen_ai.usage.output_tokens", Map.get(usage, :output_tokens, 0)}
            ])

            Events.emit_llm_call(%{
              duration_ms: duration_ms,
              input_tokens: Map.get(usage, :input_tokens, 0),
              output_tokens: Map.get(usage, :output_tokens, 0),
              provider: to_string(provider.name),
              model: provider.model
            })

            Events.emit_codegen(%{
              duration_ms: duration_ms,
              template_type: template,
              description_length: String.length(description)
            })

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

      {:error, reason} ->
        Logger.error("LLM generation failed: #{inspect(reason)}")
        {:error, extract_error_message(reason)}
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

  defp extract_error_message(%{reason: reason}) when is_binary(reason), do: reason
  defp extract_error_message(reason) when is_binary(reason), do: reason
  defp extract_error_message(reason) when is_atom(reason), do: reason
  defp extract_error_message(reason), do: inspect(reason)

  @spec extract_code(String.t()) :: {:ok, String.t()} | {:error, :no_code_in_response}
  def extract_code(response) do
    case Regex.run(~r/```(?:elixir)?\n(.*?)```/s, response) do
      [_, code] -> {:ok, String.trim(code)}
      nil -> {:error, :no_code_in_response}
    end
  end
end
