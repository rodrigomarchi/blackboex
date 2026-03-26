defmodule Blackboex.CodeGen.GenerationWorker do
  @moduledoc """
  Oban worker that generates API code from a natural language description.

  Runs independently of any UI — the user can reload, switch browsers, or go
  offline while generation proceeds. Progress is broadcast via PubSub so any
  connected LiveView can show real-time updates.

  Steps:
  1. Classify description → template type
  2. Stream LLM code generation (broadcasting tokens via PubSub)
  3. Validate: format → compile → credo → generate tests → run tests
  4. Save source_code + test_code to the API record and create version v1
  """

  use Oban.Worker, queue: :generation, max_attempts: 2, unique: [keys: [:api_id]]

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.Pipeline
  alias Blackboex.CodeGen.UnifiedPipeline
  alias Blackboex.LLM
  alias Blackboex.LLM.{Config, Prompts}
  alias Blackboex.Repo

  @pubsub Blackboex.PubSub

  # ── Public ───────────────────────────────────────────────────────────────

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"api_id" => api_id} = args}) do
    api = Repo.get(Api, api_id)

    cond do
      is_nil(api) ->
        Logger.warning("GenerationWorker: API #{api_id} not found, skipping")
        :ok

      api.generation_status != "pending" ->
        Logger.info(
          "GenerationWorker: API #{api_id} status is #{api.generation_status}, skipping"
        )

        :ok

      true ->
        run_generation(api, args)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp run_generation(api, args) do
    description = args["description"] || api.description || ""
    user_id = args["user_id"]
    org_id = args["org_id"]

    update_status(api, "generating")

    case generate_code(api.id, description) do
      {:ok, code, template, generation_meta} ->
        validate_and_save(api, code, template, description, generation_meta, user_id, org_id)

      {:error, reason} ->
        fail(api, "Code generation failed: #{format_error(reason)}")
    end
  end

  defp generate_code(api_id, description) do
    template = Pipeline.classify_type(description)
    provider = Config.default_provider()
    prompt = Prompts.build_generation_prompt(description, template)
    system = Prompts.system_prompt()
    client = Config.client()
    start_time = System.monotonic_time(:millisecond)

    case client.stream_text(prompt, model: provider.model, system: system) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        full_response = consume_stream(api_id, response)
        finalize_code(full_response, template, provider, start_time)

      {:ok, stream} ->
        full_response = consume_plain_stream(api_id, stream)
        finalize_code(full_response, template, provider, start_time)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp consume_stream(api_id, %ReqLLM.StreamResponse{} = response) do
    response
    |> ReqLLM.StreamResponse.tokens()
    |> Enum.reduce("", fn token, acc ->
      broadcast(api_id, {:generation_token, token})
      acc <> token
    end)
  end

  defp consume_plain_stream(api_id, stream) do
    Enum.reduce(stream, "", fn {:token, token}, acc ->
      broadcast(api_id, {:generation_token, token})
      acc <> token
    end)
  end

  defp finalize_code(full_response, template, provider, start_time) do
    case Pipeline.extract_code(full_response) do
      {:ok, code} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        meta = %{
          provider: to_string(provider.name),
          model: provider.model,
          tokens_used: String.length(full_response),
          output_tokens: String.length(full_response),
          duration_ms: duration_ms
        }

        {:ok, code, template, meta}

      {:error, _} ->
        {:error, :no_code_in_response}
    end
  end

  defp validate_and_save(api, code, template, description, generation_meta, user_id, org_id) do
    update_status(api, "validating")

    progress_callback = fn progress ->
      broadcast(api.id, {:generation_progress, progress})
    end

    case UnifiedPipeline.validate_and_test(code, template, progress_callback: progress_callback) do
      {:ok, result} ->
        save_result(api, result, template, description, generation_meta, user_id, org_id)

      {:error, reason} ->
        fail(api, "Validation failed: #{inspect(reason)}")
    end
  end

  defp save_result(api, result, template, description, generation_meta, user_id, org_id) do
    attrs = %{
      source_code: result.code,
      test_code: result.test_code,
      template_type: to_string(template),
      generation_status: "completed",
      generation_error: nil
    }

    case Apis.update_api(api, attrs) do
      {:ok, updated_api} ->
        Apis.create_version(updated_api, %{
          code: result.code,
          test_code: result.test_code,
          source: "ai_generation",
          prompt: description
        })

        maybe_record_usage(generation_meta, user_id, org_id)

        broadcast(
          api.id,
          {:generation_complete,
           %{
             code: result.code,
             test_code: result.test_code,
             validation: result.validation,
             template: template
           }}
        )

        :ok

      {:error, changeset} ->
        fail(api, "Failed to save: #{inspect(changeset.errors)}")
    end
  end

  defp fail(api, reason) do
    Logger.warning("GenerationWorker: #{reason} for API #{api.id}")

    Apis.update_api(api, %{
      generation_status: "failed",
      generation_error: String.slice(to_string(reason), 0, 500)
    })

    broadcast(api.id, {:generation_failed, reason})
    {:error, reason}
  end

  defp update_status(api, status) do
    Apis.update_api(api, %{generation_status: status})
    broadcast(api.id, {:generation_status, status})
  end

  defp broadcast(api_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, "api:#{api_id}", message)
  end

  defp format_error(%{reason: reason}) when is_binary(reason), do: reason
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason), do: inspect(reason, limit: 5, printable_limit: 200)

  defp maybe_record_usage(meta, user_id, org_id)
       when not is_nil(user_id) and not is_nil(org_id) do
    LLM.record_usage(%{
      user_id: user_id,
      organization_id: org_id,
      provider: meta.provider,
      model: meta.model,
      input_tokens: max(meta.tokens_used - meta.output_tokens, 0),
      output_tokens: meta.output_tokens,
      cost_cents: 0,
      operation: "code_generation",
      duration_ms: meta.duration_ms
    })
  end

  defp maybe_record_usage(_meta, _user_id, _org_id), do: :ok
end
