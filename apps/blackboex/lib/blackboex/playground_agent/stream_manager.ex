defmodule Blackboex.PlaygroundAgent.StreamManager do
  @moduledoc """
  Streaming helpers for the Playground AI pipeline.

  Buffers LLM tokens in the process dictionary and flushes batches (20+ chars
  or a newline) as PubSub `:code_delta` messages to the run topic. The
  LiveView subscribes to that topic and renders the streaming code block in
  the chat tab.
  """

  @accum_key :pg_agent_stream_accum
  @state_key :pg_agent_stream_state
  @flush_key :pg_agent_stream_flush_buffer
  @emitted_key :pg_agent_stream_emitted_len
  @min_flush_chars 20

  # State machine:
  #   :before_fence — still looking for the opening ```elixir / ```ex / ``` fence;
  #                   tokens are accumulated but NOT emitted.
  #   :inside_fence — the opening fence was found; everything up to (but not
  #                   including) the closing ``` is emitted as :code_delta.
  #   :after_fence  — the closing fence was found; further tokens are ignored.

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

    if buf != "" and Process.get(@state_key) == :inside_fence do
      Process.put(@flush_key, "")
      broadcast_delta(run_id, buf)
    else
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
      :before_fence -> try_open_fence(run_id, accum)
      :inside_fence -> try_continue_or_close(run_id, accum)
      :after_fence -> :ok
    end
  end

  # Look for an opening ```elixir / ```ex / ``` line in the accumulated text.
  # Once found, transition to :inside_fence and start emitting from right
  # after the opening newline.
  defp try_open_fence(run_id, accum) do
    case Regex.run(~r/```(?:elixir|ex)?\s*\n/, accum, return: :index) do
      [{start, len}] ->
        code_start = start + len
        Process.put(@state_key, :inside_fence)
        Process.put(@emitted_key, code_start)
        # Whatever's already past the fence header flushes out.
        emit_pending(run_id, accum, force: true)

      nil ->
        :ok
    end
  end

  defp try_continue_or_close(run_id, accum) do
    emitted = Process.get(@emitted_key, 0)
    rest = binary_slice_safe(accum, emitted)

    case find_close_fence(rest) do
      nil ->
        emit_pending(run_id, accum)

      {close_start, _close_len} ->
        # Emit up to (but not including) the ``` and stop.
        to_emit_len = close_start
        to_emit = binary_slice_safe(rest, 0, to_emit_len)
        flush_with(run_id, to_emit, force: true)
        Process.put(@emitted_key, emitted + to_emit_len)
        Process.put(@state_key, :after_fence)
    end
  end

  # Find a closing fence at the start of a line (``` followed by newline or
  # end-of-input). Avoids confusing an inline triple-backtick inside a
  # docstring — the prompts tell the model to use one fence only, so this is
  # a safe heuristic.
  defp find_close_fence(rest) do
    case Regex.run(~r/(?:^|\n)```(?:$|\n)/, rest, return: :index) do
      [{pos, _len}] ->
        # Skip the leading newline if present so we don't emit it.
        newline_offset = if binary_slice_safe(rest, pos, 1) == "\n", do: 1, else: 0
        {pos + newline_offset, 3}

      nil ->
        nil
    end
  end

  # Emit the portion of the accumulated text that's past what we've already
  # broadcast, buffering small chunks until we have either ≥20 chars or a
  # newline. `force: true` flushes whatever is there.
  defp emit_pending(run_id, accum, opts \\ []) do
    emitted = Process.get(@emitted_key, 0)
    new_chunk = binary_slice_safe(accum, emitted)

    if new_chunk == "" do
      :ok
    else
      Process.put(@emitted_key, emitted + byte_size(new_chunk))
      flush_with(run_id, new_chunk, opts)
    end
  end

  defp flush_with(_run_id, "", _opts), do: :ok

  defp flush_with(run_id, chunk, opts) do
    buf = Process.get(@flush_key, "") <> chunk
    force? = Keyword.get(opts, :force, false)

    cond do
      buf == "" ->
        :ok

      force? or String.length(buf) >= @min_flush_chars or String.contains?(chunk, "\n") ->
        Process.put(@flush_key, "")
        broadcast_delta(run_id, buf)

      true ->
        Process.put(@flush_key, buf)
        :ok
    end
  end

  defp binary_slice_safe(str, start) when is_binary(str) do
    byte_size = byte_size(str)

    cond do
      start >= byte_size -> ""
      start <= 0 -> str
      true -> binary_part(str, start, byte_size - start)
    end
  end

  defp binary_slice_safe(str, start, len) when is_binary(str) do
    total = byte_size(str)

    cond do
      start >= total -> ""
      start + len > total -> binary_part(str, start, total - start)
      true -> binary_part(str, start, len)
    end
  end

  @spec broadcast_run(String.t(), tuple()) :: :ok
  def broadcast_run(run_id, message) when is_binary(run_id) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, "playground_agent:run:#{run_id}", message)
  end

  @spec broadcast_playground(String.t(), tuple()) :: :ok
  def broadcast_playground(playground_id, message) when is_binary(playground_id) do
    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "playground_agent:playground:#{playground_id}",
      message
    )
  end

  defp broadcast_delta(run_id, delta) do
    broadcast_run(run_id, {:code_delta, %{delta: delta, run_id: run_id}})
  end
end
