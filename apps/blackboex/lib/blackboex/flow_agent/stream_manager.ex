defmodule Blackboex.FlowAgent.StreamManager do
  @moduledoc """
  Streaming helpers for the FlowAgent pipeline.

  Buffers LLM tokens in the process dictionary and flushes batches (20+ chars
  or a newline) as PubSub `:definition_delta` messages to the run topic. The
  LiveView subscribes to that topic and renders the streaming JSON block in
  the chat panel.
  """

  @accum_key :flow_agent_stream_accum
  @state_key :flow_agent_stream_state
  @flush_key :flow_agent_stream_flush_buffer
  @emitted_key :flow_agent_stream_emitted_len
  @min_flush_chars 20
  # Threshold beyond which a fence-less response is assumed to be explain mode
  # and tokens start streaming. Tuned so we decide quickly enough for latency
  # while still absorbing a slow "~~~" fence opening if the LLM fronts it.
  @explain_threshold_bytes 40

  # State machine:
  #   :before_fence — waiting for opening ~~~json / ~~~ / ```json fence.
  #   :inside_fence — opening fence found; emitting tokens until close fence
  #                   as :definition_delta (edit mode).
  #   :in_explain   — decided this is conversational prose; emitting tokens
  #                   as :explain_delta. Skips a leading "Answer:" prefix.
  #   :after_fence  — close fence seen; further tokens discarded.

  @spec build_token_callback(String.t()) :: (String.t() -> :ok)
  def build_token_callback(run_id) when is_binary(run_id) do
    reset_state()

    fn token ->
      handle_token(run_id, token)
      :ok
    end
  end

  @spec flush_remaining(String.t()) :: :ok
  def flush_remaining(run_id) when is_binary(run_id) do
    buf = Process.get(@flush_key, "")

    cond do
      buf == "" ->
        Process.put(@flush_key, "")

      Process.get(@state_key) == :inside_fence ->
        Process.put(@flush_key, "")
        broadcast_definition_delta(run_id, buf)

      Process.get(@state_key) == :in_explain ->
        Process.put(@flush_key, "")
        broadcast_explain_delta(run_id, buf)

      true ->
        Process.put(@flush_key, "")
    end

    :ok
  end

  defp reset_state do
    Process.put(@accum_key, "")
    Process.put(@state_key, :before_fence)
    Process.put(@flush_key, "")
    Process.put(@emitted_key, 0)
  end

  defp handle_token(run_id, token) do
    accum = Process.get(@accum_key, "") <> token
    Process.put(@accum_key, accum)

    case Process.get(@state_key, :before_fence) do
      :before_fence -> try_open_fence_or_explain(run_id, accum)
      :inside_fence -> try_continue_or_close(run_id, accum)
      :in_explain -> emit_explain_pending(run_id, accum)
      :after_fence -> :ok
    end
  end

  defp try_open_fence_or_explain(run_id, accum) do
    case Regex.run(~r/(?:~~~|```)(?:json)?\s*\n/, accum, return: :index) do
      [{start, len}] ->
        code_start = start + len
        Process.put(@state_key, :inside_fence)
        Process.put(@emitted_key, code_start)
        emit_definition_pending(run_id, accum, force: true)

      nil ->
        maybe_switch_to_explain(run_id, accum)
    end
  end

  # Once we have enough accumulated bytes without a fence in sight, commit
  # to explain mode: strip a leading `Answer:` prefix (and surrounding
  # whitespace) and mark everything past that point as emittable prose.
  defp maybe_switch_to_explain(run_id, accum) do
    if byte_size(accum) >= @explain_threshold_bytes do
      start = explain_content_offset(accum)
      Process.put(@state_key, :in_explain)
      Process.put(@emitted_key, start)
      emit_explain_pending(run_id, accum)
    else
      :ok
    end
  end

  defp explain_content_offset(accum) do
    case Regex.run(~r/^\s*Answer:\s*/s, accum, return: :index) do
      [{_, len}] -> len
      nil -> 0
    end
  end

  defp try_continue_or_close(run_id, accum) do
    emitted = Process.get(@emitted_key, 0)
    rest = binary_slice_safe(accum, emitted)

    case find_close_fence(rest) do
      nil ->
        emit_definition_pending(run_id, accum)

      {close_start, _close_len} ->
        to_emit_len = close_start
        to_emit = binary_slice_safe(rest, 0, to_emit_len)
        flush_with(run_id, to_emit, &broadcast_definition_delta/2, force: true)
        Process.put(@emitted_key, emitted + to_emit_len)
        Process.put(@state_key, :after_fence)
    end
  end

  defp find_close_fence(rest) do
    case Regex.run(~r/(?:^|\n)(?:~~~|```)(?:$|\n)/, rest, return: :index) do
      [{pos, _len}] ->
        newline_offset = if binary_slice_safe(rest, pos, 1) == "\n", do: 1, else: 0
        {pos + newline_offset, 3}

      nil ->
        nil
    end
  end

  defp emit_definition_pending(run_id, accum, opts \\ []) do
    emit_pending(run_id, accum, &broadcast_definition_delta/2, opts)
  end

  defp emit_explain_pending(run_id, accum) do
    emit_pending(run_id, accum, &broadcast_explain_delta/2, [])
  end

  defp emit_pending(run_id, accum, broadcaster, opts) do
    emitted = Process.get(@emitted_key, 0)
    new_chunk = binary_slice_safe(accum, emitted)

    if new_chunk == "" do
      :ok
    else
      Process.put(@emitted_key, emitted + byte_size(new_chunk))
      flush_with(run_id, new_chunk, broadcaster, opts)
    end
  end

  defp flush_with(_run_id, "", _broadcaster, _opts), do: :ok

  defp flush_with(run_id, chunk, broadcaster, opts) do
    buf = Process.get(@flush_key, "") <> chunk
    force? = Keyword.get(opts, :force, false)

    cond do
      buf == "" ->
        :ok

      force? or String.length(buf) >= @min_flush_chars or String.contains?(chunk, "\n") ->
        Process.put(@flush_key, "")
        broadcaster.(run_id, buf)

      true ->
        Process.put(@flush_key, buf)
        :ok
    end
  end

  # byte_size-based slicing: `emitted` tracks byte offsets because the regex
  # indices returned by `Regex.run(..., return: :index)` are also byte-based
  # for non-unicode patterns. A multi-byte UTF-8 token arriving mid-fence
  # would still be emitted atomically (we only ever split on newline or
  # min-flush thresholds, not inside a token).
  defp binary_slice_safe(str, start) when is_binary(str) do
    size = byte_size(str)

    cond do
      start >= size -> ""
      start <= 0 -> str
      true -> safe_binary_part(str, start, size - start)
    end
  end

  defp binary_slice_safe(str, start, len) when is_binary(str) do
    total = byte_size(str)

    cond do
      start >= total -> ""
      start + len > total -> safe_binary_part(str, start, total - start)
      true -> safe_binary_part(str, start, len)
    end
  end

  # Guard against codepoint splits: if `binary_part` would land mid-codepoint
  # and produce an invalid UTF-8 binary, fall back to the empty string so the
  # caller just waits for more tokens. This keeps the process dict's byte
  # counter consistent while never emitting garbled UTF-8 to the UI.
  defp safe_binary_part(str, start, len) do
    slice = binary_part(str, start, len)
    if String.valid?(slice), do: slice, else: ""
  end

  @spec broadcast_run(String.t(), tuple()) :: :ok
  def broadcast_run(run_id, message) when is_binary(run_id) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, "flow_agent:run:#{run_id}", message)
  end

  @spec broadcast_flow(String.t(), tuple()) :: :ok
  def broadcast_flow(flow_id, message) when is_binary(flow_id) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, "flow_agent:flow:#{flow_id}", message)
  end

  defp broadcast_definition_delta(run_id, delta) do
    broadcast_run(run_id, {:definition_delta, %{delta: delta, run_id: run_id}})
  end

  defp broadcast_explain_delta(run_id, delta) do
    broadcast_run(run_id, {:explain_delta, %{delta: delta, run_id: run_id}})
  end
end
