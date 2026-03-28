defmodule Blackboex.Agent.Callbacks do
  @moduledoc """
  LangChain callback handlers that persist events to the database
  and broadcast progress via PubSub for LiveView consumption.

  Each callback creates an Event record and emits a PubSub message.
  Streaming deltas are broadcast with content for real-time UI updates.
  Tool executions emit telemetry for observability.

  ## PubSub Protocol

  ### Topics

  - `"api:\#{api_id}"` — receives `{:agent_run_started, ...}` from KickoffWorker
  - `"run:\#{run_id}"` — receives all other agent events from Callbacks and Session

  ### Message Shapes (topic: `"run:\#{run_id}"`)

  | Message | Payload | Source |
  |---------|---------|--------|
  | `{:agent_started, payload}` | `%{run_id, run_type}` | Session |
  | `{:agent_streaming, payload}` | `%{delta, run_id}` | Callbacks (on_llm_new_delta) |
  | `{:agent_message, payload}` | `%{role, content, run_id}` | Callbacks (on_message_processed) |
  | `{:agent_action, payload}` | `%{tool, run_id}` | Callbacks (on_tool_call_identified) |
  | `{:tool_started, payload}` | `%{tool, run_id}` | Callbacks (on_tool_execution_started) |
  | `{:tool_result, payload}` | `%{tool, success, summary, run_id}` | Callbacks (on_tool_execution_completed) |
  | `{:guardrail_triggered, payload}` | `%{type, run_id}` | Callbacks (persist_guardrail_event) |
  | `{:agent_completed, payload}` | `%{code, test_code, summary, run_id, status}` | Session |
  | `{:agent_failed, payload}` | `%{error, run_id}` | Session |

  ### Message Shape (topic: `"api:\#{api_id}"`)

  | Message | Payload | Source |
  |---------|---------|--------|
  | `{:agent_run_started, payload}` | `%{run_id, run_type}` | KickoffWorker |

  ### Subscription Lifecycle

  1. LiveView subscribes to `"api:\#{api_id}"` on mount
  2. On `{:agent_run_started}`, LiveView subscribes to `"run:\#{run_id}"`
  3. On `{:agent_completed}` or `{:agent_failed}`, LiveView sets `current_run_id` to nil
  """

  require Logger

  alias Blackboex.Agent.Guardrails
  alias Blackboex.Conversations
  alias Blackboex.Conversations.Event
  alias Blackboex.Telemetry.Events

  @type session_context :: %{
          run_id: String.t(),
          conversation_id: String.t(),
          session_pid: pid() | nil
        }

  @doc "Builds a callback handler map for LangChain LLMChain."
  @spec build(session_context()) :: map()
  def build(%{run_id: run_id, conversation_id: conversation_id} = ctx) do
    %{
      on_llm_new_delta: fn _chain, deltas ->
        handle_streaming_deltas(deltas, run_id)
      end,
      on_message_processed: fn _chain, message ->
        handle_message_processed(message, run_id, conversation_id)
      end,
      on_tool_call_identified: fn _chain, tool_call, _func ->
        handle_tool_call_identified(tool_call, run_id, conversation_id)
      end,
      on_tool_execution_started: fn _chain, tool_call, _func ->
        broadcast(run_id, {:tool_started, %{tool: tool_call.name, run_id: run_id}})
      end,
      on_tool_execution_completed: fn _chain, tool_call, result ->
        handle_tool_completed(tool_call, result, run_id, conversation_id)
      end,
      on_tool_execution_failed: fn _chain, tool_call, error ->
        handle_tool_failed(tool_call, error, run_id, conversation_id)
      end,
      on_retries_exceeded: fn _chain ->
        handle_retries_exceeded(run_id, conversation_id)

        if pid = Map.get(ctx, :session_pid) do
          send(pid, :retries_exceeded)
        end
      end
    }
  end

  # ── Handlers ───────────────────────────────────────────────────

  defp handle_streaming_deltas(deltas, run_id) do
    # Extract text content from deltas — handles both string content and ContentPart structs
    text =
      deltas
      |> List.wrap()
      |> Enum.map_join("", &extract_delta_text/1)

    if text != "" do
      broadcast(run_id, {:agent_streaming, %{delta: text, run_id: run_id}})
    end
  end

  defp extract_delta_text(delta) when is_binary(delta), do: delta

  defp extract_delta_text(%{content: content}) when is_binary(content), do: content

  defp extract_delta_text(%{content: parts}) when is_list(parts) do
    Enum.map_join(parts, "", &extract_content_part/1)
  end

  defp extract_delta_text(_), do: ""

  defp extract_content_part(%{type: :text, content: text}) when is_binary(text), do: text
  defp extract_content_part(%{content: text}) when is_binary(text), do: text
  defp extract_content_part(_), do: ""

  defp handle_message_processed(message, run_id, conversation_id) do
    {event_type, role} = classify_message(message)
    content = extract_content(message)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: event_type,
      role: role,
      content: content
    })

    broadcast(run_id, {:agent_message, %{role: role, content: content, run_id: run_id}})
  end

  defp classify_message(message) do
    case message.role do
      :assistant -> {"assistant_message", "assistant"}
      :user -> {"user_message", "user"}
      :system -> {"system_message", "system"}
      _ -> {"assistant_message", "assistant"}
    end
  end

  defp handle_tool_call_identified(tool_call, run_id, conversation_id) do
    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_call",
      tool_name: tool_call.name,
      tool_input: tool_call.arguments || %{}
    })

    broadcast(run_id, {:agent_action, %{tool: tool_call.name, run_id: run_id}})
  end

  defp handle_tool_completed(tool_call, result, run_id, conversation_id) do
    content = extract_tool_result_content(result)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_result",
      tool_name: tool_call.name,
      tool_success: true,
      content: content
    })

    Events.emit_agent_tool(%{
      tool_name: tool_call.name,
      success: true,
      run_id: run_id,
      duration_ms: 0
    })

    broadcast(run_id, {
      :tool_result,
      %{tool: tool_call.name, success: true, summary: truncate(content, 200), run_id: run_id}
    })
  end

  defp handle_tool_failed(tool_call, error, run_id, conversation_id) do
    error_msg = if is_binary(error), do: error, else: inspect(error)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_result",
      tool_name: tool_call.name,
      tool_success: false,
      content: error_msg
    })

    Events.emit_agent_tool(%{
      tool_name: tool_call.name,
      success: false,
      run_id: run_id,
      duration_ms: 0
    })

    broadcast(run_id, {
      :tool_result,
      %{
        tool: tool_call.name,
        success: false,
        summary: truncate(error_msg, 200),
        run_id: run_id
      }
    })
  end

  defp handle_retries_exceeded(run_id, conversation_id) do
    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "error",
      content: "LLM retries exceeded"
    })
  end

  # ── Guardrail Event ────────────────────────────────────────────

  @doc "Persists a guardrail trigger event and broadcasts it."
  @spec persist_guardrail_event(String.t(), String.t(), atom()) :: :ok
  def persist_guardrail_event(run_id, conversation_id, reason) do
    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "guardrail_trigger",
      content: Guardrails.reason_message(reason),
      metadata: %{"guardrail_type" => to_string(reason)}
    })

    broadcast(run_id, {:guardrail_triggered, %{type: reason, run_id: run_id}})
    :ok
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp persist_event(attrs) do
    run_id = attrs.run_id
    seq = Conversations.next_sequence(run_id)

    case Conversations.append_event(Map.put(attrs, :sequence, seq)) do
      {:ok, %Event{}} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to persist event: #{inspect(changeset.errors)}",
          run_id: run_id,
          event_type: attrs[:event_type]
        )

        :ok
    end
  end

  defp broadcast(run_id, message) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, "run:#{run_id}", message)
  end

  defp extract_content(message) do
    case message.content do
      content when is_binary(content) -> content
      parts when is_list(parts) -> Enum.map_join(parts, "\n", &extract_content_part/1)
      nil -> ""
      other -> inspect(other)
    end
  end

  defp extract_tool_result_content(result) do
    cond do
      is_binary(result) -> result
      is_map(result) and is_binary(result.content) -> result.content
      is_map(result) and is_list(result.content) -> Enum.map_join(result.content, "\n", &extract_content_part/1)
      is_map(result) and Map.has_key?(result, :content) -> inspect(result.content)
      true -> inspect(result)
    end
  end

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."
end
