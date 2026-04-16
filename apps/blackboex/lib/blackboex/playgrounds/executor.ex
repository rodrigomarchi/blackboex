defmodule Blackboex.Playgrounds.Executor do
  @moduledoc """
  Executes playground code in a sandboxed environment.

  Uses `ASTValidator.validate/1` for initial security validation, then applies
  additional playground-specific checks (allowlist approach for module calls,
  blocking dynamic module construction, Function.capture, defmodule).

  Evaluates the pre-validated AST via `Code.eval_quoted/2` inside a
  process-isolated sandbox with heap and timeout limits.

  Reuses the existing `SandboxTaskSupervisor` from the application supervision tree.
  """

  alias Blackboex.CodeGen.ASTValidator

  @max_heap_size 10_485_760
  @timeout 5_000
  @max_output_length 65_536

  # Allowlist of safe modules for playground use
  @allowed_modules ~w(
    Enum Map List String Integer Float Tuple Keyword MapSet
    Date Time DateTime NaiveDateTime Calendar Regex URI Base
    Jason Access Stream Range Atom IO Inspect Kernel
    Map.Merge Bitwise
  )

  @rate_limit_window 60_000
  @rate_limit_max 10

  @spec execute(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(source_code) when is_binary(source_code) do
    with {:ok, ast} <- validate(source_code),
         :ok <- validate_playground_safety(ast) do
      run_sandboxed(ast)
    end
  end

  @spec execute(String.t(), integer() | String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(source_code, user_id) when is_binary(source_code) do
    with :ok <- check_rate_limit(user_id),
         {:ok, ast} <- validate(source_code),
         :ok <- validate_playground_safety(ast) do
      run_sandboxed(ast)
    end
  end

  defp check_rate_limit(user_id) do
    bucket = "playground_exec:#{user_id}"

    case ExRated.check_rate(bucket, @rate_limit_window, @rate_limit_max) do
      {:ok, _count} ->
        :ok

      {:error, _limit} ->
        {:error, "Rate limit exceeded: max #{@rate_limit_max} executions per minute"}
    end
  end

  defp validate(source_code) do
    case ASTValidator.validate(source_code) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, errors} when is_list(errors) ->
        {:error, Enum.join(errors, "; ")}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  # Additional playground-specific AST safety checks beyond ASTValidator
  defp validate_playground_safety(ast) do
    {_, violations} = Macro.prewalk(ast, [], &check_node/2)

    case violations do
      [] -> :ok
      msgs -> {:error, Enum.join(Enum.reverse(msgs), "; ")}
    end
  end

  # Block defmodule — prevents polluting the global module namespace
  defp check_node({:defmodule, _meta, _args} = node, acc) do
    {node, ["defmodule is not allowed in playgrounds" | acc]}
  end

  # Block dynamic atom construction of module names (:"Elixir.System" bypass)
  defp check_node(atom, acc) when is_atom(atom) do
    atom_str = Atom.to_string(atom)

    if String.starts_with?(atom_str, "Elixir.") do
      module_name = String.replace_prefix(atom_str, "Elixir.", "")

      if module_name not in @allowed_modules do
        {atom, ["dynamic module reference not allowed: #{module_name}" | acc]}
      else
        {atom, acc}
      end
    else
      {atom, acc}
    end
  end

  # Block Function.capture (bypass vector for prohibited modules)
  defp check_node(
         {{:., _meta1, [{:__aliases__, _meta2, [:Function]}, :capture]}, _meta3, _args} = node,
         acc
       ) do
    {node, ["Function.capture is not allowed in playgrounds" | acc]}
  end

  # Block :erlang, :os, :file and other dangerous Erlang module calls
  defp check_node({{:., _meta1, [module, _func]}, _meta2, _args} = node, acc)
       when is_atom(module) do
    module_str = Atom.to_string(module)

    if module_str in ~w(erlang os file io code port process ets dets) do
      {node, ["Erlang module :#{module_str} is not allowed" | acc]}
    else
      {node, acc}
    end
  end

  # Block Kernel module calls that are dangerous
  defp check_node(
         {{:., _meta1, [{:__aliases__, _meta2, parts}, _func]}, _meta3, _args} = node,
         acc
       ) do
    module_str = Enum.map_join(parts, ".", &to_string/1)

    if module_str in @allowed_modules do
      {node, acc}
    else
      {node, ["module not allowed: #{module_str}" | acc]}
    end
  end

  # Allow everything else (literals, operators, local function calls, etc.)
  defp check_node(node, acc) do
    {node, acc}
  end

  defp run_sandboxed(ast) do
    task =
      Task.Supervisor.async_nolink(
        Blackboex.SandboxTaskSupervisor,
        fn ->
          Process.flag(:max_heap_size, %{size: @max_heap_size, kill: true, error_logger: false})

          try do
            {result, _bindings} = Code.eval_quoted(ast, [])
            output = inspect(result, pretty: true, limit: 1000)
            {:ok, String.slice(output, 0, @max_output_length)}
          rescue
            e -> {:error, Exception.message(e)}
          catch
            kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
          end
        end
      )

    case Task.yield(task, @timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      {:exit, {:killed, _}} ->
        {:error, "Execution killed: memory limit exceeded"}

      {:exit, reason} ->
        {:error, "Execution failed: #{inspect(reason)}"}

      nil ->
        {:error, "Execution timed out after #{@timeout}ms"}
    end
  end
end
