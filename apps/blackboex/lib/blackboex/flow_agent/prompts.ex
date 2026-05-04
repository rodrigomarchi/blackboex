defmodule Blackboex.FlowAgent.Prompts do
  @moduledoc """
  System and user prompts for the FlowAgent. Teaches the LLM the canonical
  `BlackboexFlow` JSON schema, lists every node type with its `data` fields,
  and injects three real templates as few-shot examples.

  Output contract enforced by `DefinitionParser`:

      ~~~json
      {"version":"1.0","nodes":[...],"edges":[...]}
      ~~~

  Optionally followed by a single `Summary:` line.
  """

  alias Blackboex.FlowAgent.Prompts.Examples

  @type run_type :: :generate | :edit

  @max_history_chars 500
  # Unicode zero-width space used to neutralize user-supplied fence openers.
  @zwsp "\u200B"

  @structural_contract """
  STRUCTURAL CONTRACT (validated before saving):
  - version = "1.0"
  - nodes: list of objects with id, type, position:{x,y}, data fields
  - node ids in "n1", "n2", "n3"... format (regex: ^n\\d+$)
  - edges: list of objects with id, source, source_port (int), target, target_port (int)
  - Exactly ONE "start" node; at least one "end" node
  - No cycles; no fan-in (each target port receives at most 1 edge)
  - No self-loops; no duplicate edges (same source_port to target_port pair)
  - source_port must respect fixed outputs for the type (condition is dynamic; others are fixed at 1)
  """

  @node_catalog """
  NODE TYPES (data fields):

  - start: execution_mode ("sync"|"async"), timeout (ms), payload_schema [],
    state_schema []. Schemas are lists of {name, type, required, constraints,
    initial_value}. Type ∈ {string, integer, float, boolean, array, object}.

  - elixir_code: code (Elixir string that returns tuple {output, new_state}).
    Optional timeout via timeout_ms.

  - condition: expression (Elixir that returns int 0..N output port),
    branch_labels (map {"0": "Yes", "1": "No"} for canvas labels).

  - end: response_schema [], response_mapping [{response_field, state_variable}].

  - http_request: method ("GET"|"POST"|"PUT"|"PATCH"|"DELETE"),
    url (accepts {{state.X}} and {{input.X}}), headers (map), body_template (string),
    timeout_ms, max_retries, expected_status [], auth_type, auth_config.

  - delay: duration_ms, max_duration_ms.

  - for_each: source_expression (Elixir that returns a list), body_code (Elixir),
    item_variable ("item"), accumulator (state field name).

  - webhook_wait: event_type (string), timeout_ms, resume_path (optional).

  - sub_flow: flow_id (UUID of another active flow), input_mapping {...},
    timeout_ms (optional).

  - fail: message (string), include_state (boolean).

  - debug: expression (Elixir), log_level ("info"|"warn"|"error"), state_key.
  """

  @output_format """
  TWO OPERATION MODES (choose based on the request):

  1. EDIT MODE - when the request asks to CREATE, MODIFY, ADD, REMOVE,
     CONNECT, or REFACTOR the flow. Produce the COMPLETE definition:

     ~~~json
     {"version":"1.0","nodes":[...],"edges":[...]}
     ~~~

     Optionally, add one "Summary: ..." line AFTER the block describing what
     you did in one sentence.

  2. EXPLAIN MODE - when the request asks to EXPLAIN, DESCRIBE, SUMMARIZE,
     ANALYZE, or answer a question about the current flow (for example:
     "explain how this works", "what is this node for", "how does this
     condition decide"). DO NOT emit a JSON block. Respond in simple markdown
     and start exactly with `Answer:`:

     ```
     Answer: <your explanation in English, lists and headings are allowed>
     ```

     In this mode the flow is NOT modified; you only discuss it.

  GOLDEN RULE: when unsure, if the user did not use action verbs
  (create, add, remove, edit...), prefer explain mode. Never alter the flow
  without clear user intent.

  POSITIONING (edit mode only):
  - Distribute nodes in columns (x += 200) by topological depth
  - Use rows (y += 150) per branch, useful for conditions with multiple outputs
  - If `position` is omitted, auto-layout will be applied
  """

  @few_shot Examples.few_shot_json()

  @system_generate """
  You are an assistant that DESIGNS executable Blackboex flows. Given a user
  request, produce the full canonical flow definition in JSON.

  #{@structural_contract}

  #{@node_catalog}

  #{@output_format}

  REAL EXAMPLES (use as style and structure references):

  #{@few_shot}
  """

  @system_edit """
  You are an assistant that EDITS executable Blackboex flows. Given the
  current flow and a change request, apply ONLY the requested change while
  preserving every other node, edge, and position that does not need to change.

  IMPORTANT:
  - Preserve nodes, edges, positions, and configs unrelated to the request
  - DO NOT rewrite the whole flow for aesthetics
  - Return the COMPLETE edited definition (never diffs/patches)
  - Keep existing IDs; add new ones only for new nodes

  #{@structural_contract}

  #{@node_catalog}

  #{@output_format}

  REAL EXAMPLES (use as style and structure references):

  #{@few_shot}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message for a run. For `:generate`, only the request is
  passed (plus optional history). For `:edit`, the current definition is
  included above the request inside a `~~~json` fence.

  Options:

    * `:history` — list of `%{role, content}` maps from previous turns of the
      current thread, oldest-first. Rendered as "Conversation history:" so
      the LLM behaves like a real thread instead of a one-shot.
  """
  @spec user_message(run_type(), String.t(), map() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) ::
          String.t()
  def user_message(run_type, message, definition_before, opts \\ [])

  def user_message(run_type, message, definition_before, opts) when is_list(opts) do
    history = Keyword.get(opts, :history, [])
    build_user_message(run_type, message, definition_before, history)
  end

  def user_message(run_type, message, definition_before, %{} = attrs) do
    user_message(run_type, message, definition_before, Enum.into(attrs, []))
  end

  defp build_user_message(:generate, message, _definition_before, history) do
    """
    #{render_history(history)}User request:
    #{sanitize(message)}
    """
  end

  defp build_user_message(:edit, message, definition_before, history) do
    current_json = serialize_definition(definition_before)

    """
    #{render_history(history)}Current flow definition:
    ~~~json
    #{current_json}
    ~~~

    User request:
    #{sanitize(message)}
    """
  end

  defp render_history([]), do: ""

  defp render_history(history) do
    lines =
      history
      |> Enum.map(fn
        %{role: "user", content: c} -> "- User: #{truncate(c)}"
        %{role: "assistant", content: c} -> "- Assistant: #{truncate(c)}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case lines do
      [] -> ""
      _ -> "Conversation history (previous messages):\n" <> Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @max_history_chars do
      String.slice(text, 0, @max_history_chars) <> "..."
    else
      text
    end
  end

  defp truncate(_), do: ""

  # Defensive: if the user message starts lines with `~~~` the LLM could be
  # tricked into closing our fence early. Prepend a zero-width space to any
  # leading triple-tilde/triple-backtick sequence so the neutralized version
  # is no longer a valid markdown fence.
  defp sanitize(message) when is_binary(message) do
    message
    |> String.replace(~r/(^|\n)(~~~|```)/, "\\1" <> @zwsp <> "\\2")
  end

  defp sanitize(_), do: ""

  defp serialize_definition(nil), do: "{}"
  defp serialize_definition(definition) when is_map(definition), do: Jason.encode!(definition)
  defp serialize_definition(_), do: "{}"
end
