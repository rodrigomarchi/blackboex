defmodule Blackboex.CodeGen.DiffEngine do
  @moduledoc """
  Computes line-level diffs and applies search/replace edits.
  """

  @spec compute_diff(String.t(), String.t()) :: [{:eq | :ins | :del, [String.t()]}]
  def compute_diff(old_code, new_code) do
    old_lines = String.split(old_code, "\n")
    new_lines = String.split(new_code, "\n")
    List.myers_difference(old_lines, new_lines)
  end

  @spec format_diff_summary([{:eq | :ins | :del, [String.t()]}]) :: String.t()
  def format_diff_summary(diff) do
    {added, removed} =
      Enum.reduce(diff, {0, 0}, fn
        {:ins, lines}, {a, r} -> {a + length(lines), r}
        {:del, lines}, {a, r} -> {a, r + length(lines)}
        {:eq, _lines}, acc -> acc
      end)

    parts =
      []
      |> then(fn acc -> if added > 0, do: ["#{added} added" | acc], else: acc end)
      |> then(fn acc -> if removed > 0, do: ["#{removed} removed" | acc], else: acc end)
      |> Enum.reverse()

    case parts do
      [] -> "no changes"
      _ -> Enum.join(parts, ", ")
    end
  end

  @doc """
  Applies SEARCH/REPLACE blocks to code. Each block's SEARCH text must match
  a contiguous section of the code exactly. Tries exact match first, then
  fuzzy match ignoring trailing whitespace.
  """
  @spec apply_search_replace(String.t(), [%{search: String.t(), replace: String.t()}]) ::
          {:ok, String.t()} | {:error, :search_not_found, String.t()}
  def apply_search_replace(code, blocks) do
    Enum.reduce_while(blocks, {:ok, code}, fn block, {:ok, current} ->
      cond do
        String.contains?(current, block.search) ->
          {:cont, {:ok, String.replace(current, block.search, block.replace, global: false)}}

        String.contains?(normalize_ws(current), normalize_ws(block.search)) ->
          {:cont, {:ok, replace_fuzzy(current, block.search, block.replace)}}

        true ->
          {:halt, {:error, :search_not_found, block.search}}
      end
    end)
  end

  defp normalize_ws(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  defp replace_fuzzy(code, search, replace) do
    normalized_code = normalize_ws(code)
    normalized_search = normalize_ws(search)

    case :binary.match(normalized_code, normalized_search) do
      {start, len} ->
        # Find the corresponding position in the original code
        before = binary_part(code, 0, start)
        after_pos = start + len
        after_text = binary_part(code, after_pos, byte_size(code) - after_pos)
        before <> replace <> after_text

      :nomatch ->
        code
    end
  end
end
