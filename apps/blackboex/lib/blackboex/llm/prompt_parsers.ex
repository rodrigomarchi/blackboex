defmodule Blackboex.LLM.PromptParsers do
  @moduledoc """
  Canonical source for LLM response parsing and prompt sanitization utilities.

  All response format parsing (code blocks, SEARCH/REPLACE, section markers)
  and input sanitization (code fence escaping, field truncation) live here.
  Prompt modules delegate to these functions rather than defining their own.
  """

  # ── Code Block Extraction ─────────────────────────────────────

  @doc "Extracts code from a ```elixir code block. Returns tagged tuple."
  @spec parse_code_block(String.t()) :: {:ok, String.t()} | {:error, :no_code_found}
  def parse_code_block(response) do
    case Regex.run(~r/```(?:elixir)?\s*[\r\n](.*?)```/s, response) do
      [_, code] -> {:ok, String.trim(code)}
      _ -> {:error, :no_code_found}
    end
  end

  # ── SEARCH/REPLACE Parsing ────────────────────────────────────

  @doc "Parse SEARCH/REPLACE blocks from LLM response into structured edits."
  @spec parse_search_replace_blocks(String.t()) :: [%{search: String.t(), replace: String.t()}]
  def parse_search_replace_blocks(response) do
    # Normalize Windows line endings (\r\n) to Unix (\n) before parsing.
    # LLMs can return either format depending on training data.
    normalized = String.replace(response, "\r\n", "\n")

    ~r/<<<<<<< SEARCH\n(.*?)=======\n(.*?)>>>>>>> REPLACE/s
    |> Regex.scan(normalized)
    |> Enum.map(fn [_, search, replace] ->
      %{search: String.trim_trailing(search, "\n"), replace: String.trim_trailing(replace, "\n")}
    end)
  end

  @doc "Parse the ---CODE--- / ---TESTS--- format with SEARCH/REPLACE blocks."
  @spec parse_test_fix_edits(String.t()) ::
          {[%{search: String.t(), replace: String.t()}],
           [%{search: String.t(), replace: String.t()}]}
          | :error
  def parse_test_fix_edits(response) do
    code_section =
      case Regex.run(~r/---CODE---\s*\n(.*?)(?=---TESTS---|$)/s, response) do
        [_, section] -> parse_search_replace_blocks(section)
        nil -> []
      end

    test_section =
      case Regex.run(~r/---TESTS---\s*\n(.*)/s, response) do
        [_, section] -> parse_search_replace_blocks(section)
        nil -> []
      end

    if code_section == [] and test_section == [] do
      :error
    else
      {code_section, test_section}
    end
  end

  @doc "Parse the ---CODE--- / ---TESTS--- format from test fix responses (legacy full-code format)."
  @spec parse_code_and_tests(String.t()) :: {String.t(), String.t()} | :error
  def parse_code_and_tests(response) do
    case Regex.run(~r/---CODE---\s*\n(.*?)---TESTS---\s*\n(.*)/s, response) do
      [_, code, tests] -> {String.trim(code), String.trim(tests)}
      nil -> :error
    end
  end

  # ── Sanitization ──────────────────────────────────────────────

  @doc "Escape triple backticks in user content to prevent prompt structure breakout."
  @spec sanitize_code_fence(String.t()) :: String.t()
  def sanitize_code_fence(text) do
    String.replace(text, "```", "` ` `")
  end

  @doc "Strip backticks from user-provided text fields and cap length."
  @spec sanitize_field(String.t()) :: String.t()
  def sanitize_field(text) do
    text
    |> String.replace(~r/[```]/, "")
    |> String.slice(0, 10_000)
  end
end
