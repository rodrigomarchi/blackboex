defmodule Blackboex.Apis.DiffEngine do
  @moduledoc """
  Computes line-level diffs between code versions using List.myers_difference/2.
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
end
