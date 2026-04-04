defmodule Blackboex.CodeGen.Linter do
  @moduledoc """
  Runs code quality checks (format, Credo-style) on user-generated handler code.

  Implements inline AST-based checks for the most important code quality rules
  rather than invoking Credo on temp files, ensuring reliability and speed.
  """

  @type check_result :: %{
          check: :format | :credo,
          status: :pass | :warn | :error,
          issues: [String.t()]
        }

  @max_line_length 120
  @max_function_lines 40
  @max_nesting_depth 4

  @doc "Run all lint checks on handler code."
  @spec run_all(String.t()) :: [check_result()]
  def run_all(code) when is_binary(code) do
    [check_format(code), check_credo(code)]
  end

  @doc "Check if code is properly formatted."
  @spec check_format(String.t()) :: check_result()
  def check_format(code) when is_binary(code) do
    formatted = Code.format_string!(code) |> IO.iodata_to_binary()

    if formatted == code do
      %{check: :format, status: :pass, issues: []}
    else
      %{check: :format, status: :warn, issues: ["Code is not formatted according to mix format"]}
    end
  rescue
    e ->
      %{
        check: :format,
        status: :error,
        issues: ["Format check failed: #{Exception.message(e)}"]
      }
  end

  @doc "Auto-format code and return the formatted version."
  @spec auto_format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def auto_format(code) when is_binary(code) do
    formatted = Code.format_string!(code) |> IO.iodata_to_binary()
    {:ok, formatted}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Run Credo-style checks on handler code via AST analysis."
  @spec check_credo(String.t()) :: check_result()
  def check_credo(code) when is_binary(code) do
    issues =
      []
      |> check_long_lines(code)
      |> check_missing_specs(code)
      |> check_missing_docs(code)
      |> check_function_length(code)
      |> check_nesting_depth(code)
      |> Enum.reverse()

    status = if issues == [], do: :pass, else: :warn
    %{check: :credo, status: status, issues: issues}
  end

  # --- Long lines check ---

  @spec check_long_lines([String.t()], String.t()) :: [String.t()]
  defp check_long_lines(acc, code) do
    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {line, line_no}, issues ->
      if String.length(line) > @max_line_length do
        [
          "Line #{line_no} exceeds #{@max_line_length} characters (#{String.length(line)})"
          | issues
        ]
      else
        issues
      end
    end)
  end

  # --- Missing @spec on public functions ---

  @spec check_missing_specs([String.t()], String.t()) :: [String.t()]
  defp check_missing_specs(acc, code) do
    case Code.string_to_quoted(code, columns: true) do
      {:ok, ast} ->
        public_fns = extract_public_functions(ast)
        spec_names = extract_spec_names(ast)
        collect_missing_specs(public_fns, spec_names, acc)

      {:error, _} ->
        acc
    end
  end

  defp collect_missing_specs(public_fns, spec_names, acc) do
    Enum.reduce(public_fns, acc, fn {name, arity, line}, issues ->
      if MapSet.member?(spec_names, {name, arity}) do
        issues
      else
        ["Missing @spec for #{name}/#{arity} (line #{line})" | issues]
      end
    end)
  end

  # --- Missing @doc on public functions ---

  @spec check_missing_docs([String.t()], String.t()) :: [String.t()]
  defp check_missing_docs(acc, code) do
    lines = String.split(code, "\n")

    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {line, line_no}, issues ->
      trimmed = String.trim(line)
      check_doc_for_line(trimmed, lines, line_no, issues)
    end)
  end

  defp check_doc_for_line(trimmed, lines, line_no, issues) do
    if public_function_def?(trimmed) do
      check_doc_presence(trimmed, lines, line_no, issues)
    else
      issues
    end
  end

  defp public_function_def?(trimmed) do
    String.starts_with?(trimmed, "def ") and not String.starts_with?(trimmed, "defp ") and
      not String.starts_with?(trimmed, "defmodule ") and
      not String.starts_with?(trimmed, "defmacro") and
      not String.starts_with?(trimmed, "defdelegate") and
      not String.starts_with?(trimmed, "defguard")
  end

  defp check_doc_presence(trimmed, lines, line_no, issues) do
    if has_doc_above?(lines, line_no - 1) do
      issues
    else
      fn_name = extract_function_name_from_line(trimmed)
      ["Missing @doc for public function #{fn_name} (line #{line_no})" | issues]
    end
  end

  # --- Function length check ---

  @spec check_function_length([String.t()], String.t()) :: [String.t()]
  defp check_function_length(acc, code) do
    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({acc, nil, 0}, &track_function_length/2)
    |> elem(0)
  end

  defp track_function_length({line, line_no}, {issues, current_fn, depth}) do
    trimmed = String.trim(line)
    is_def = function_def?(trimmed)
    process_tracked_line(is_def, trimmed, line_no, issues, current_fn, depth)
  end

  defp function_def?(trimmed) do
    String.starts_with?(trimmed, "def ") or String.starts_with?(trimmed, "defp ")
  end

  defp process_tracked_line(true, trimmed, line_no, issues, _current_fn, 0) do
    start_new_function(trimmed, line_no, issues)
  end

  defp process_tracked_line(true, trimmed, line_no, issues, current_fn, _depth)
       when current_fn != nil do
    close_and_start_function(current_fn, trimmed, line_no, issues)
  end

  defp process_tracked_line(false, "end", line_no, issues, current_fn, 1)
       when current_fn != nil do
    close_function(current_fn, line_no, issues)
  end

  defp process_tracked_line(false, trimmed, _line_no, issues, current_fn, depth)
       when current_fn != nil do
    new_depth = depth + count_depth_change(trimmed)
    {issues, current_fn, max(new_depth, 1)}
  end

  defp process_tracked_line(_is_def, _trimmed, _line_no, issues, current_fn, depth) do
    {issues, current_fn, depth}
  end

  defp start_new_function(trimmed, line_no, issues) do
    fn_name = extract_function_name_from_line(trimmed)
    {issues, {fn_name, line_no, 1}, 1}
  end

  defp close_and_start_function(current_fn, trimmed, line_no, issues) do
    new_issues = maybe_report_long_function(current_fn, line_no, issues)
    new_fn_name = extract_function_name_from_line(trimmed)
    {new_issues, {new_fn_name, line_no, 1}, 1}
  end

  defp close_function(current_fn, line_no, issues) do
    new_issues = maybe_report_long_function(current_fn, line_no, issues)
    {new_issues, nil, 0}
  end

  defp maybe_report_long_function({fn_name, start_line, _}, line_no, issues) do
    line_count = line_no - start_line

    if line_count > @max_function_lines do
      [
        "Function #{fn_name} is too long (#{line_count} lines, max #{@max_function_lines}) starting at line #{start_line}"
        | issues
      ]
    else
      issues
    end
  end

  # --- Nesting depth check ---

  @spec check_nesting_depth([String.t()], String.t()) :: [String.t()]
  defp check_nesting_depth(acc, code) do
    case Code.string_to_quoted(code, columns: true) do
      {:ok, ast} ->
        check_ast_nesting(ast, 0, acc)

      {:error, _} ->
        acc
    end
  end

  defp check_ast_nesting({block, meta, args}, depth, acc)
       when block in [:if, :unless, :case, :cond, :with] and is_list(args) do
    line = Keyword.get(meta, :line, 0)

    acc =
      if depth > @max_nesting_depth do
        [
          "Deeply nested #{block} block at line #{line} (depth #{depth}, max #{@max_nesting_depth})"
          | acc
        ]
      else
        acc
      end

    check_ast_children(args, depth + 1, acc)
  end

  defp check_ast_nesting({_form, _meta, args}, depth, acc) when is_list(args) do
    check_ast_children(args, depth, acc)
  end

  defp check_ast_nesting({left, right}, depth, acc) do
    acc = check_ast_nesting(left, depth, acc)
    check_ast_nesting(right, depth, acc)
  end

  defp check_ast_nesting(list, depth, acc) when is_list(list) do
    Enum.reduce(list, acc, &check_ast_nesting(&1, depth, &2))
  end

  defp check_ast_nesting(_leaf, _depth, acc), do: acc

  defp check_ast_children(children, depth, acc) when is_list(children) do
    Enum.reduce(children, acc, &check_ast_nesting(&1, depth, &2))
  end

  defp check_ast_children(_children, _depth, acc), do: acc

  # --- Helpers ---

  defp extract_public_functions(ast) do
    {_, fns} =
      Macro.prewalk(ast, [], fn
        {:def, meta, [{:when, _, [{name, _, args} | _]} | _]} = node, acc
        when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          line = Keyword.get(meta, :line, 0)
          {node, [{name, arity, line} | acc]}

        {:def, meta, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          line = Keyword.get(meta, :line, 0)
          {node, [{name, arity, line} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(fns)
  end

  defp extract_spec_names(ast) do
    {_, specs} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:@, _, [{:spec, _, [{:"::", _, [{name, _, args} | _]} | _]}]} = node, acc
        when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          {node, MapSet.put(acc, {name, arity})}

        # Handle spec with when clause
        {:@, _, [{:spec, _, [{:when, _, [{:"::", _, [{name, _, args} | _]} | _]} | _]}]} = node,
        acc
        when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          {node, MapSet.put(acc, {name, arity})}

        node, acc ->
          {node, acc}
      end)

    specs
  end

  defp has_doc_above?(_lines, target_line_no) when target_line_no < 1, do: false

  defp has_doc_above?(lines, target_line_no) do
    # Look backwards from the line before the function def for @doc
    # Skip blank lines and @spec lines
    prev_idx = target_line_no - 1

    if prev_idx < 0 do
      false
    else
      lines
      |> Enum.slice(max(0, prev_idx - 10)..prev_idx)
      |> Enum.reverse()
      |> Enum.reduce_while(false, &classify_preceding_line/2)
    end
  end

  defp classify_preceding_line(line, _found) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> {:cont, false}
      String.starts_with?(trimmed, "@spec") -> {:cont, false}
      String.starts_with?(trimmed, "@doc") -> {:halt, true}
      String.starts_with?(trimmed, ~s(""")) -> {:halt, true}
      true -> {:halt, false}
    end
  end

  defp extract_function_name_from_line(line) do
    case Regex.run(~r/^defp?\s+([a-z_][a-z0-9_?!]*)/, line) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  defp count_depth_change(line) do
    openers =
      Regex.scan(~r/\b(do|fn)\b/, line)
      |> length()

    closers =
      Regex.scan(~r/\bend\b/, line)
      |> length()

    openers - closers
  end
end
