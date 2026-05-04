defmodule Blackboex.PlaygroundAgent.Prompts do
  @moduledoc """
  System and user prompts for the Playground AI agent. The prompts teach the
  model about the sandbox environment (`Blackboex.Playgrounds.Executor`):
  allowed modules, custom helpers, and the required response format.

  Prompts are intentionally specific to the Playground's single-file Elixir
  execution model — different from the multi-file API generation prompts.
  """

  @type run_type :: :generate | :edit

  @environment_rules """
  EXECUTION ENVIRONMENT (strict sandbox):
  - Elixir 1.15+ running with a 15s timeout and max 10MB heap
  - Output captured through IO.puts / IO.inspect (max 64KB)
  - The final expression value is inspected at the end
  - FORBIDDEN: defmodule, Function.capture, File, System, :erlang, :os, :code, :port
  - HTTP: max 5 calls per execution, 3s timeout, SSRF blocked (no private IPs)

  ALLOWED MODULES (Elixir stdlib):
  Enum, Map, List, String, Integer, Float, Tuple, Keyword, MapSet, Date, Time,
  DateTime, NaiveDateTime, Calendar, Regex, URI, Base, Jason, Access, Stream,
  Range, Atom, IO, Inspect, Kernel, Bitwise

  CUSTOM HELPERS (explicit alias):
  - Blackboex.Playgrounds.Http — get/2, post/3, put/3, patch/3, delete/2.
    Returns {:ok, %{status, headers, body}} | {:error, reason}.
  - Blackboex.Playgrounds.Api — call_flow/2, call_api/5 (auth helpers).

  REQUIRED STYLE:
  - English comments explaining the "why"
  - IO.puts for readable output (do not rely only on final result inspection)
  - Pattern matching in case/cond instead of nested if/else
  - Pipe operator |> for chaining transformations
  - Handle errors explicitly with {:ok, _} | {:error, _}

  RESPONSE FORMAT:
  Return EXACTLY one complete Elixir code block, with no prose before or after:

  ```elixir
  # full code here
  ```

  Optionally, add one English line starting with "Summary:" AFTER the block,
  describing what the script does in one sentence.
  """

  @system_generate """
  You are an assistant that writes single-file Elixir scripts to run in the
  Blackboex Playground. Given a user request, produce functional, readable,
  idiomatic code that runs in the sandbox described below.

  #{@environment_rules}
  """

  @system_edit """
  You are an assistant that EDITS single-file Elixir scripts for the Blackboex
  Playground. Given the current code and a change request, apply ONLY the
  requested change while preserving existing style, comments, and structure.

  IMPORTANT:
  - Preserve original comments and code style whenever possible
  - DO NOT rewrite parts unrelated to the request
  - Return the COMPLETE edited code (never diffs/patches)

  #{@environment_rules}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message for a run. Optional `history` is a list of
  `%{role, content}` maps from previous turns of the current thread, oldest
  first; it gets rendered as a "Conversation history:" block so the LLM has
  context and behaves like a real thread.

  For `:generate`, only the request (plus optional history) is passed. For
  `:edit`, the current code is included above the request.
  """
  @spec user_message(run_type(), String.t(), String.t() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) ::
          String.t()
  def user_message(run_type, message, code_before, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    history_block = render_history(history)

    case run_type do
      :generate ->
        """
        #{history_block}User request:
        #{message}
        """

      :edit ->
        current = code_before || ""

        """
        #{history_block}Current code:
        ```elixir
        #{current}
        ```

        User request:
        #{message}
        """
    end
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
      [] ->
        ""

      _ ->
        "Conversation history (previous messages):\n" <>
          Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > 500 do
      String.slice(text, 0, 500) <> "..."
    else
      text
    end
  end

  defp truncate(_), do: ""
end
