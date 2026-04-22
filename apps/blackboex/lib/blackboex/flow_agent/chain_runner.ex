defmodule Blackboex.FlowAgent.ChainRunner do
  @moduledoc """
  Runs the FlowAgent definition pipeline inside a Session's Task and
  translates the result back into persisted run state + PubSub broadcasts.
  """

  require Logger

  alias Blackboex.FlowAgent.DefinitionPipeline
  alias Blackboex.FlowAgent.Session
  alias Blackboex.FlowAgent.StreamManager
  alias Blackboex.FlowConversations
  alias Blackboex.Flows

  @type chain_result :: %{
          required(:kind) => :edit | :explain,
          optional(:definition) => map(),
          optional(:summary) => String.t(),
          optional(:answer) => String.t(),
          required(:input_tokens) => non_neg_integer(),
          required(:output_tokens) => non_neg_integer()
        }

  @spec run_chain(Session.t()) :: {:ok, chain_result()} | {:error, term()}
  def run_chain(%Session{} = state) do
    token_callback = StreamManager.build_token_callback(state.run_id)

    history =
      state.flow_id
      |> FlowConversations.thread_history(limit: 10)
      |> drop_current_user_message(state.trigger_message)

    DefinitionPipeline.run(
      state.run_type,
      state.trigger_message,
      state.definition_before,
      run_id: state.run_id,
      token_callback: token_callback,
      history: history
    )
  end

  # The KickoffWorker already persisted the current user_message event before
  # the Session started; strip it from history so the LLM doesn't see the same
  # message twice (once as history, once as the current request).
  defp drop_current_user_message([], _message), do: []

  defp drop_current_user_message(history, message) do
    case List.last(history) do
      %{role: "user", content: ^message} -> Enum.drop(history, -1)
      _ -> history
    end
  end

  @spec handle_chain_success(Session.t(), chain_result()) :: :ok
  def handle_chain_success(state, %{kind: :explain} = result) do
    run = FlowConversations.get_run!(state.run_id)

    _ =
      FlowConversations.append_event(run, %{
        event_type: "completed",
        content: result.answer,
        metadata: %{
          kind: "explain",
          input_tokens: result.input_tokens,
          output_tokens: result.output_tokens
        }
      })

    {:ok, completed} =
      FlowConversations.complete_run(run, %{
        run_summary: result.answer,
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cost_cents: 0
      })

    FlowConversations.increment_conversation_stats(
      FlowConversations.get_conversation(run.conversation_id),
      total_runs: 1,
      total_events: 2,
      total_input_tokens: result.input_tokens,
      total_output_tokens: result.output_tokens
    )

    # No `definition` key — the LiveView's pattern-match for :run_completed
    # distinguishes explain vs. edit and skips the canvas reload for explain.
    payload = %{
      kind: :explain,
      answer: result.answer,
      run_id: state.run_id,
      run: completed
    }

    StreamManager.broadcast_run(state.run_id, {:run_completed, payload})
    StreamManager.broadcast_flow(state.flow_id, {:run_completed, Map.delete(payload, :run)})
    :ok
  end

  def handle_chain_success(state, %{kind: :edit, definition: definition} = result) do
    run = FlowConversations.get_run!(state.run_id)
    flow = Flows.get_flow(state.organization_id, state.flow_id)
    scope = %{organization: %{id: state.organization_id}}

    case apply_edit(flow, definition, scope) do
      {:ok, _applied} ->
        _ =
          FlowConversations.append_event(run, %{
            event_type: "completed",
            content: result.summary,
            metadata: %{
              kind: "edit",
              input_tokens: result.input_tokens,
              output_tokens: result.output_tokens
            }
          })

        {:ok, completed} =
          FlowConversations.complete_run(run, %{
            definition_after: definition,
            run_summary: result.summary,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cost_cents: 0
          })

        FlowConversations.increment_conversation_stats(
          FlowConversations.get_conversation(run.conversation_id),
          total_runs: 1,
          total_events: 2,
          total_input_tokens: result.input_tokens,
          total_output_tokens: result.output_tokens
        )

        payload = %{
          kind: :edit,
          definition: definition,
          summary: result.summary,
          run_id: state.run_id
        }

        StreamManager.broadcast_run(state.run_id, {:run_completed, Map.put(payload, :run, completed)})
        StreamManager.broadcast_flow(state.flow_id, {:run_completed, payload})
        :ok

      {:error, reason} ->
        Logger.warning("record_ai_edit failed: #{inspect(reason)}")
        handle_chain_failure(state, "falha ao aplicar edição: #{inspect(reason)}")
    end
  end

  @spec handle_chain_failure(Session.t(), term()) :: :ok
  def handle_chain_failure(state, error) do
    reason = format_error(error)

    # DB persistence may fail if the database is unreachable; we still want to
    # unblock the LiveView, so the broadcast must always fire.
    try do
      run = FlowConversations.get_run!(state.run_id)
      _ = FlowConversations.append_event(run, %{event_type: "failed", content: reason})
      {:ok, _} = FlowConversations.fail_run(run, reason)
    rescue
      error ->
        Logger.error(
          "FlowAgent handle_chain_failure DB persistence failed for run " <>
            "#{state.run_id}: #{Exception.message(error)}"
        )
    end

    StreamManager.broadcast_run(
      state.run_id,
      {:run_failed, %{reason: reason, run_id: state.run_id}}
    )

    StreamManager.broadcast_flow(
      state.flow_id,
      {:run_failed, %{reason: reason, run_id: state.run_id}}
    )

    :ok
  end

  @spec handle_circuit_open(Session.t()) :: :ok
  def handle_circuit_open(state) do
    handle_chain_failure(state, "Circuit breaker do LLM aberto — tente novamente em instantes")
  end

  # ── helpers ──────────────────────────────────────────────

  defp apply_edit(nil, _definition, _scope), do: {:error, :flow_not_found}

  defp apply_edit(flow, definition, scope) do
    Flows.record_ai_edit(flow, definition, scope)
  end

  defp format_error({:crashed, reason}), do: "Processo do agente crashou: #{inspect(reason)}"
  defp format_error(:no_json_block), do: "resposta do modelo não continha bloco JSON"

  defp format_error({:invalid_json, reason}) when is_binary(reason),
    do: "JSON inválido: #{reason}"

  defp format_error({:invalid_json, reason}), do: "JSON inválido: #{inspect(reason)}"

  defp format_error({:invalid_flow, reason}) when is_binary(reason),
    do: "Fluxo inválido: #{reason}"

  defp format_error({:invalid_flow, reason}), do: "Fluxo inválido: #{inspect(reason)}"
  defp format_error(err) when is_binary(err), do: err
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(err), do: inspect(err)
end
