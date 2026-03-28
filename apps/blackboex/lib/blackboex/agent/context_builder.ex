defmodule Blackboex.Agent.ContextBuilder do
  @moduledoc """
  Builds LLM context from previous runs in a conversation.

  For the current run, the agent sees full detail. For previous runs,
  only summaries are included to preserve context window budget.
  """

  alias Blackboex.Conversations

  @max_previous_runs 5

  @doc """
  Builds a formatted string of previous run summaries for inclusion
  in the LLM system prompt. Returns empty string if no previous runs.
  """
  @spec build_previous_context(String.t()) :: String.t()
  def build_previous_context(conversation_id) do
    runs = Conversations.run_summary_for_context(conversation_id, @max_previous_runs)

    case runs do
      [] ->
        ""

      runs ->
        entries =
          Enum.map_join(runs, "\n", fn run ->
            summary = run.run_summary || "(no summary)"

            "- [#{run.run_type}] \"#{run.trigger_message}\" -> #{run.status}\n  Summary: #{summary}"
          end)

        """
        ## Previous Work on This API
        #{entries}
        """
    end
  end
end
