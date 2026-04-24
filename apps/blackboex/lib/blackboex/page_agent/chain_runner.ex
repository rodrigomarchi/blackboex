defmodule Blackboex.PageAgent.ChainRunner do
  @moduledoc """
  Runs the markdown content pipeline for a `PageAgent.Session` and translates
  the result back into persisted run state + PubSub broadcasts.

  Pure functions — no GenServer state. Called from the Session's `Task` and
  also directly by the Session for circuit-open / failure short-circuits.
  """

  require Logger

  alias Blackboex.PageAgent.ContentPipeline
  alias Blackboex.PageAgent.Session
  alias Blackboex.PageAgent.StreamManager
  alias Blackboex.PageConversations
  alias Blackboex.Pages

  @type chain_result :: %{
          content: String.t(),
          summary: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @spec run_chain(Session.t()) :: {:ok, chain_result()} | {:error, term()}
  def run_chain(%Session{} = state) do
    token_callback = StreamManager.build_token_callback(state.run_id)

    # Re-read content from the DB to minimize the race window where the user
    # edits the page after the Oban job is enqueued but before the LLM runs.
    content_before =
      case Pages.get_for_org(state.organization_id, state.page_id) do
        nil -> state.content_before || ""
        %{content: content} -> content || ""
      end

    history =
      state.page_id
      |> PageConversations.thread_history(limit: 10)
      |> drop_current_user_message(state.trigger_message)

    ContentPipeline.run(state.run_type, state.trigger_message, content_before,
      run_id: state.run_id,
      token_callback: token_callback,
      history: history,
      project_id: state.project_id
    )
  end

  defp drop_current_user_message([], _message), do: []

  defp drop_current_user_message(history, message) do
    case List.last(history) do
      %{role: "user", content: ^message} -> Enum.drop(history, -1)
      _ -> history
    end
  end

  @spec handle_chain_success(Session.t(), chain_result()) :: :ok
  def handle_chain_success(state, %{content: content} = result) do
    case PageConversations.get_run(state.run_id) do
      nil ->
        Logger.warning("PageRun #{state.run_id} disappeared during execution; skipping success")
        :ok

      run ->
        do_handle_success(state, run, content, result)
    end
  end

  defp do_handle_success(state, run, content, result) do
    page = Pages.get_for_org(state.organization_id, state.page_id)
    scope = %{user: %{id: state.user_id}, organization: %{id: state.organization_id}}

    case apply_edit(page, content, scope) do
      {:ok, _applied} ->
        _ =
          PageConversations.append_event(run, %{
            event_type: "completed",
            content: result.summary,
            metadata: %{
              input_tokens: result.input_tokens,
              output_tokens: result.output_tokens
            }
          })

        {:ok, completed} =
          PageConversations.complete_run(run, %{
            content_after: content,
            run_summary: result.summary,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cost_cents: 0
          })

        PageConversations.increment_conversation_stats(
          PageConversations.get_conversation(run.conversation_id),
          total_runs: 1,
          total_events: 2,
          total_input_tokens: result.input_tokens,
          total_output_tokens: result.output_tokens
        )

        broadcast_completion(state, content, result.summary, completed)
        :ok

      {:error, reason} ->
        Logger.warning("Pages.record_ai_edit failed: #{inspect(reason)}")
        handle_chain_failure(state, "falha ao aplicar edição: #{inspect(reason)}")
    end
  end

  @spec handle_chain_failure(Session.t(), term()) :: :ok
  def handle_chain_failure(state, error) do
    reason = format_error(error)

    case PageConversations.get_run(state.run_id) do
      nil ->
        Logger.warning("PageRun #{state.run_id} disappeared before failure recorded")
        broadcast_failure(state, reason)
        :ok

      run ->
        _ = PageConversations.append_event(run, %{event_type: "failed", content: reason})
        {:ok, _} = PageConversations.fail_run(run, reason)
        broadcast_failure(state, reason)
        :ok
    end
  end

  @spec handle_circuit_open(Session.t()) :: :ok
  def handle_circuit_open(state) do
    handle_chain_failure(state, "Circuit breaker do LLM aberto — tente novamente em instantes")
  end

  defp apply_edit(nil, _content, _scope), do: {:error, :page_not_found}

  defp apply_edit(page, content, scope) do
    Pages.record_ai_edit(page, content, scope)
  end

  defp broadcast_completion(state, content, summary, run) do
    payload = %{content: content, summary: summary, run_id: state.run_id, run: run}
    StreamManager.broadcast_run(state.run_id, {:run_completed, payload})
    StreamManager.broadcast_page(state.organization_id, state.page_id, {:run_completed, payload})
  end

  defp broadcast_failure(state, reason) do
    payload = %{reason: reason, run_id: state.run_id}
    StreamManager.broadcast_run(state.run_id, {:run_failed, payload})
    StreamManager.broadcast_page(state.organization_id, state.page_id, {:run_failed, payload})
  end

  # Generic, non-leaky error messages. Internals are logged at warn level for
  # operators; the user sees a stable phrase regardless of the actual reason.
  defp format_error({:crashed, reason}) do
    Logger.warning("PageAgent task crashed: #{inspect(reason)}")
    "Erro interno do agente. Tente novamente."
  end

  defp format_error(err) when is_binary(err), do: err

  defp format_error(%{message: msg}) when is_binary(msg), do: msg

  defp format_error(err) do
    Logger.warning("PageAgent unexpected error: #{inspect(err)}")
    "Erro inesperado. Tente novamente."
  end
end
