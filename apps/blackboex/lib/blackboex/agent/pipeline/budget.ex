defmodule Blackboex.Agent.Pipeline.Budget do
  @moduledoc """
  LLM call budgeting, counters, context logging, and streaming control for the code pipeline.

  The LLM `{client, llm_opts}` tuple must be passed explicitly via
  `guarded_llm_call/3`. It is **not** stored in the process dictionary so
  Tasks / re-entrant callers always use the resolved pair instead of a
  stale snapshot.
  """

  require Logger

  alias Blackboex.Conversations
  alias Blackboex.LogSanitizer

  @max_total_llm_calls 15

  @type llm_ctx :: {module(), keyword()}

  @doc """
  Guarded LLM call — prevents runaway loops across all fix steps.

  The `{client, llm_opts}` context is passed explicitly so there is no
  global / process-dictionary state. Streaming uses `:token_callback`
  from the process dictionary (which is set per-pipeline by the caller
  and flipped on/off during the run — see `disable_streaming/0` and
  `restore_streaming/1`).
  """
  @spec guarded_llm_call(llm_ctx(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()} | {:error, :budget_exhausted}
  def guarded_llm_call({client, llm_opts}, prompt, system)
      when is_atom(client) and is_list(llm_opts) do
    count = Process.get(:pipeline_llm_calls, 0)
    max_calls = Process.get(:pipeline_max_llm_calls, @max_total_llm_calls)

    if count >= max_calls do
      {:error, :budget_exhausted}
    else
      Process.put(:pipeline_llm_calls, count + 1)
      token_callback = Process.get(:token_callback)

      if token_callback do
        stream_llm_call(client, prompt, system, token_callback, llm_opts)
      else
        sync_llm_call(client, prompt, system, llm_opts)
      end
    end
  end

  @spec sync_llm_call(term(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp sync_llm_call(client, prompt, system, llm_opts) do
    case client.generate_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %{content: content} = result} ->
        accumulate_usage(result[:usage])
        {:ok, content}

      {:error, reason} ->
        {:error, "LLM call failed: #{LogSanitizer.sanitize(reason)}"}
    end
  end

  @spec stream_llm_call(term(), String.t(), String.t(), (String.t() -> :ok), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp stream_llm_call(client, prompt, system, token_callback, llm_opts) do
    case client.stream_text(prompt, Keyword.merge(llm_opts, system: system)) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        content =
          response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            token_callback.(token)
            acc <> token
          end)

        flush_stream_buffer(token_callback)
        accumulate_usage(ReqLLM.StreamResponse.usage(response))
        {:ok, content}

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

        flush_stream_buffer(token_callback)
        {:ok, content}

      {:error, reason} ->
        {:error, "LLM stream failed: #{LogSanitizer.sanitize(reason)}"}
    end
  rescue
    e ->
      Logger.debug("Stream failed, falling back to sync: #{Exception.message(e)}")
      run_id = Process.get(:pipeline_run_id)

      if run_id do
        Phoenix.PubSub.broadcast(Blackboex.PubSub, "run:#{run_id}", {:stream_reset, %{}})
      end

      sync_llm_call(client, prompt, system, llm_opts)
  end

  @spec flush_stream_buffer((String.t() -> :ok)) :: :ok
  defp flush_stream_buffer(token_callback) do
    buffer = Process.get(:stream_buffer, "")

    if buffer != "" do
      Process.put(:stream_buffer, "")
      token_callback.(buffer)
    end

    :ok
  end

  @spec reset_counters() :: term()
  def reset_counters do
    Process.put(:pipeline_llm_calls, 0)
    Process.put(:pipeline_input_tokens, 0)
    Process.put(:pipeline_output_tokens, 0)
    Process.put(:pipeline_log, [])
    Process.put(:pipeline_max_llm_calls, @max_total_llm_calls)
  end

  # ── Rolling Context Log ────────────────────────────────────────
  # Accumulates a lightweight log of pipeline steps so fix prompts
  # can include what happened before. No extra LLM calls needed.

  @spec log_step(String.t(), :pass | :fail, String.t()) :: :ok
  def log_step(step, status, detail) do
    entry = "[#{step}] #{status}: #{String.slice(detail, 0, 1000)}"
    log = Process.get(:pipeline_log, [])
    Process.put(:pipeline_log, log ++ [entry])
    :ok
  end

  @spec get_context_log() :: String.t()
  def get_context_log do
    log = Process.get(:pipeline_log, [])

    case log do
      [] -> ""
      entries -> Enum.take(entries, -10) |> Enum.join("\n")
    end
  end

  @spec accumulate_usage(map() | nil) :: :ok
  def accumulate_usage(nil), do: :ok

  def accumulate_usage(usage) when is_map(usage) do
    input = Map.get(usage, :input_tokens, 0) || Map.get(usage, "input_tokens", 0) || 0
    output = Map.get(usage, :output_tokens, 0) || Map.get(usage, "output_tokens", 0) || 0

    Process.put(:pipeline_input_tokens, Process.get(:pipeline_input_tokens, 0) + input)
    Process.put(:pipeline_output_tokens, Process.get(:pipeline_output_tokens, 0) + output)
    :ok
  end

  @spec get_accumulated_usage() :: %{input_tokens: integer(), output_tokens: integer()}
  def get_accumulated_usage do
    %{
      input_tokens: Process.get(:pipeline_input_tokens, 0),
      output_tokens: Process.get(:pipeline_output_tokens, 0)
    }
  end

  @spec disable_streaming() :: :ok
  def disable_streaming do
    Process.put(:token_callback, nil)
    :ok
  end

  @spec restore_streaming((String.t() -> :ok) | nil) :: :ok
  def restore_streaming(callback) do
    Process.put(:token_callback, callback)
    :ok
  end

  @spec set_dynamic_budget([map()], keyword()) :: :ok
  def set_dynamic_budget(manifest, opts) do
    file_count = length(manifest)
    base = opts[:max_llm_calls] || @max_total_llm_calls
    # Each file = 1 call (plan + handler + helpers + tests + docs + fix budget)
    dynamic = min(base + file_count * 3, 40)
    Process.put(:pipeline_max_llm_calls, dynamic)
    :ok
  end

  @spec save_partial(atom(), term()) :: :ok
  def save_partial(key, value) do
    Process.put({:partial, key}, value)
    :ok
  end

  @spec build_partial_result() :: term()
  def build_partial_result do
    handler_code = Process.get({:partial, :handler}, "")
    source_files = Process.get({:partial, :source_files}, [])

    files =
      if source_files != [] do
        source_files
      else
        if handler_code != "" do
          [%{path: "/src/handler.ex", content: handler_code, file_type: "source"}]
        else
          []
        end
      end

    if files == [] do
      {:error, "Pipeline exceeded LLM call budget with no code generated"}
    else
      {:ok,
       %{
         code: handler_code,
         test_code: "",
         files: files,
         test_files: [],
         documentation_md: "",
         summary: "Partial result — LLM call budget exhausted",
         partial: true,
         usage: get_accumulated_usage()
       }}
    end
  end

  @spec touch_run(String.t() | nil) :: :ok | {:ok, term()}
  def touch_run(nil), do: :ok
  def touch_run(run_id), do: Conversations.touch_run(run_id)

  @spec template_atom(String.t() | nil) :: :crud | :webhook | :computation
  def template_atom("crud"), do: :crud
  def template_atom("webhook"), do: :webhook
  def template_atom(_), do: :computation
end
