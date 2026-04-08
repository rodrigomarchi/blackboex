defmodule Blackboex.Agent.Pipeline.CodeParser do
  @moduledoc """
  Code extraction and parsing utilities for the code pipeline.
  """

  require Logger

  alias Blackboex.Agent.FixPrompts
  alias Blackboex.CodeGen.DiffEngine

  @spec extract_code(String.t()) :: String.t()
  def extract_code(response) do
    code =
      case Regex.run(~r/```(?:elixir)?\n(.*?)```/s, response) do
        [_, code] -> String.trim(code)
        nil -> String.trim(response)
      end

    # Validate the extracted text looks like Elixir code
    if code != "" and (String.contains?(code, "def ") or String.contains?(code, "defmodule")) do
      code
    else
      # Fallback: return as-is, let compiler catch the error downstream
      Logger.warning("LLM response may not contain valid code: #{String.slice(response, 0, 100)}")
      code
    end
  end

  # Tries to apply SEARCH/REPLACE edits from LLM response.
  # On failure, tries full code extraction from ```elixir blocks.
  # As last resort, keeps the original code unchanged so downstream fixes
  # operate on valid code instead of corrupted text.
  @spec apply_edits_or_extract(String.t(), String.t()) :: String.t()
  def apply_edits_or_extract(original_code, response) do
    blocks = FixPrompts.parse_search_replace_blocks(response)

    if blocks != [] do
      apply_parsed_edits(original_code, blocks, response)
    else
      safe_extract_or_keep(original_code, response)
    end
  end

  @spec apply_parsed_edits(String.t(), list(), String.t()) :: String.t()
  defp apply_parsed_edits(original_code, blocks, response) do
    case DiffEngine.apply_search_replace(original_code, blocks) do
      {:ok, patched} ->
        validate_patched_code(original_code, patched, blocks)

      {:error, :search_not_found, search_snippet} ->
        Logger.warning(
          "Search/replace failed (match not found: #{String.slice(search_snippet, 0, 80)}), trying full extraction"
        )

        safe_extract_or_keep(original_code, response)
    end
  end

  @spec validate_patched_code(String.t(), String.t(), list()) :: String.t()
  defp validate_patched_code(original_code, patched, blocks) do
    cond do
      String.contains?(patched, "<<<<<<< SEARCH") or
          String.contains?(patched, ">>>>>>> REPLACE") ->
        Logger.warning("Search/replace markers leaked into patched code, keeping original")
        original_code

      code_looks_corrupted?(original_code, patched) ->
        Logger.warning("Patched code looks corrupted (size ratio off), keeping original")
        original_code

      true ->
        Logger.debug("Applied #{length(blocks)} search/replace edit(s)")
        patched
    end
  end

  # Extracts code from ```elixir blocks, but validates it looks like real code.
  # Falls back to original code if extraction yields garbage.
  @spec safe_extract_or_keep(String.t(), String.t()) :: String.t()
  defp safe_extract_or_keep(original_code, response) do
    extracted = extract_code(response)

    if extracted != "" and not code_looks_corrupted?(original_code, extracted) do
      extracted
    else
      Logger.warning("Extracted code looks invalid, keeping original code unchanged")
      original_code
    end
  end

  # Detects if patched/extracted code is likely corrupted by checking
  # it still looks like valid Elixir and hasn't wildly changed in size.
  @spec code_looks_corrupted?(String.t(), String.t()) :: boolean()
  def code_looks_corrupted?(original, candidate) do
    orig_len = String.length(original)
    cand_len = String.length(candidate)
    has_code = String.contains?(candidate, "def ") or String.contains?(candidate, "defmodule")

    cond do
      # Candidate doesn't look like code at all
      not has_code -> true
      # Candidate shrank to less than 30% of original (likely lost code)
      orig_len > 100 and cand_len < orig_len * 0.3 -> true
      # Everything looks reasonable
      true -> false
    end
  end
end
