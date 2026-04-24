defmodule Blackboex.PlaygroundAgent.ChainRunner do
  @moduledoc """
  Runs the single-file code pipeline for a PlaygroundAgent.Session in an
  isolated Task and translates the result back into persisted run state +
  PubSub broadcasts.
  """

  require Logger

  alias Blackboex.PlaygroundAgent.CodePipeline
  alias Blackboex.PlaygroundAgent.Session
  alias Blackboex.PlaygroundAgent.StreamManager
  alias Blackboex.PlaygroundConversations
  alias Blackboex.Playgrounds

  @type chain_result :: %{
          code: String.t(),
          summary: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @spec run_chain(Session.t()) :: {:ok, chain_result()} | {:error, term()}
  def run_chain(%Session{} = state) do
    token_callback = StreamManager.build_token_callback(state.run_id)

    history =
      PlaygroundConversations.thread_history(state.playground_id, limit: 10)
      |> drop_current_user_message(state.trigger_message)

    CodePipeline.run(state.run_type, state.trigger_message, state.code_before,
      run_id: state.run_id,
      token_callback: token_callback,
      history: history,
      project_id: state.project_id
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
  def handle_chain_success(state, %{code: code} = result) do
    run = PlaygroundConversations.get_run!(state.run_id)
    playground = Playgrounds.get_playground(project_id_for(run), state.playground_id)

    case apply_edit(playground, code, state.code_before) do
      {:ok, _applied} ->
        _ =
          PlaygroundConversations.append_event(run, %{
            event_type: "completed",
            content: result.summary,
            metadata: %{
              input_tokens: result.input_tokens,
              output_tokens: result.output_tokens
            }
          })

        {:ok, completed} =
          PlaygroundConversations.complete_run(run, %{
            code_after: code,
            run_summary: result.summary,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cost_cents: 0
          })

        PlaygroundConversations.increment_conversation_stats(
          PlaygroundConversations.get_conversation(run.conversation_id),
          total_runs: 1,
          total_events: 2,
          total_input_tokens: result.input_tokens,
          total_output_tokens: result.output_tokens
        )

        StreamManager.broadcast_run(
          state.run_id,
          {:run_completed,
           %{code: code, summary: result.summary, run_id: state.run_id, run: completed}}
        )

        :ok

      {:error, reason} ->
        Logger.warning("record_ai_edit failed: #{inspect(reason)}")
        handle_chain_failure(state, "falha ao aplicar edição: #{inspect(reason)}")
    end
  end

  @spec handle_chain_failure(Session.t(), term()) :: :ok
  def handle_chain_failure(state, error) do
    reason = format_error(error)
    run = PlaygroundConversations.get_run!(state.run_id)

    _ =
      PlaygroundConversations.append_event(run, %{
        event_type: "failed",
        content: reason
      })

    {:ok, _} = PlaygroundConversations.fail_run(run, reason)

    StreamManager.broadcast_run(
      state.run_id,
      {:run_failed, %{reason: reason, run_id: state.run_id}}
    )

    :ok
  end

  @spec handle_circuit_open(Session.t()) :: :ok
  def handle_circuit_open(state) do
    handle_chain_failure(state, "Circuit breaker do LLM aberto — tente novamente em instantes")
  end

  # ── helpers ──────────────────────────────────────────────

  defp apply_edit(nil, _code, _before), do: {:error, :playground_not_found}

  defp apply_edit(playground, code, code_before) do
    Playgrounds.record_ai_edit(playground, code, code_before)
  end

  defp project_id_for(run) do
    conv = PlaygroundConversations.get_conversation(run.conversation_id)
    conv && conv.project_id
  end

  defp format_error({:crashed, reason}), do: "Processo do agente crashou: #{inspect(reason)}"
  defp format_error(err) when is_binary(err), do: err
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(err), do: inspect(err)
end
