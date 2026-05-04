defmodule Blackboex.PageAgent.StreamManager do
  @moduledoc """
  Streaming helpers for the Page AI pipeline.

  Buffers LLM tokens in the process dictionary and flushes batches (20+ chars
  or a newline) as PubSub `:content_delta` messages to the run topic. The
  LiveView subscribes to that topic and renders the streaming markdown block
  in the chat panel.

  The state machine only emits tokens that are INSIDE the outer
  `~~~markdown`/`~~~md`/`~~~` fence — prose before and after (including
  trailing `Summary:` lines) is discarded.
  """

  @accum_key :pg_page_stream_accum
  @state_key :pg_page_stream_state
  @flush_key :pg_page_stream_flush_buffer
  @emitted_key :pg_page_stream_emitted_len
  @min_flush_chars 20

  # Accept either tilde fences (preferred — allow nested backtick code blocks)
  # or backtick fences (LLM default fallback). The opener must be at line start.
  @open_fence ~r/(?:^|\n)(?:~~~|```)(?:markdown|md)?\s*\n/
  # Closing fence must match the opener style, but the regex below treats both
  # as valid since well-formed responses use a single style throughout. We
  # accept either to be lenient with LLM output.
  @close_fence ~r/(?:^|\n)(?:~~~|```)(?:$|\n)/

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

  defp try_open_fence(run_id, accum) do
    case Regex.run(@open_fence, accum, return: :index) do
      [{start, len}] ->
        content_start = start + len
        Process.put(@state_key, :inside_fence)
        Process.put(@emitted_key, content_start)
        # Re-enter the inside-fence handler so that a closing fence that
        # arrived in the same token is detected and we transition to
        # :after_fence instead of leaking later tokens.
        try_continue_or_close(run_id, accum)

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

      {close_start, _} ->
        to_emit = binary_slice_safe(rest, 0, close_start)
        flush_with(run_id, to_emit, force: true)
        Process.put(@emitted_key, emitted + close_start)
        Process.put(@state_key, :after_fence)
    end
  end

  defp find_close_fence(rest) do
    case Regex.run(@close_fence, rest, return: :index) do
      [{pos, _}] ->
        newline_offset = if binary_slice_safe(rest, pos, 1) == "\n", do: 1, else: 0
        {pos + newline_offset, 3}

      nil ->
        nil
    end
  end

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
    total = byte_size(str)

    cond do
      start >= total -> ""
      start <= 0 -> str
      true -> binary_part(str, start, total - start)
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
    Phoenix.PubSub.broadcast(Blackboex.PubSub, run_topic(run_id), message)
  end

  @spec broadcast_page(String.t(), String.t(), tuple()) :: :ok
  def broadcast_page(org_id, page_id, message) when is_binary(org_id) and is_binary(page_id) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, page_topic(org_id, page_id), message)
  end

  @doc "Per-page PubSub topic, scoped to the organization to defeat ID-guessing leaks."
  @spec page_topic(String.t(), String.t()) :: String.t()
  def page_topic(org_id, page_id), do: "page_agent:#{org_id}:page:#{page_id}"

  @doc "Per-run PubSub topic. The run id is a UUID — sufficient unguessable scoping."
  @spec run_topic(String.t()) :: String.t()
  def run_topic(run_id), do: "page_agent:run:#{run_id}"

  defp broadcast_delta(run_id, delta) do
    broadcast_run(run_id, {:content_delta, %{delta: delta, run_id: run_id}})
  end
end
