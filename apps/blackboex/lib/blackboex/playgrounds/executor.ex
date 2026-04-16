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

  @max_heap_size 10_485_760
  @timeout 15_000
  @max_output_length 65_536

  # Allowlist of safe modules for playground use
  @allowed_modules ~w(
    Enum Map List String Integer Float Tuple Keyword MapSet
    Date Time DateTime NaiveDateTime Calendar Regex URI Base
    Jason Access Stream Range Atom IO Inspect Kernel
    Map.Merge Bitwise
    Blackboex.Playgrounds.Http Blackboex.Playgrounds.Api
  )

  @rate_limit_window 60_000
  @rate_limit_max 10

  @spec allowed_modules() :: [String.t()]
  def allowed_modules, do: @allowed_modules

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

  @max_atoms 1000

  defp validate(source_code) do
    atom_counter = :counters.new(1, [:atomics])

    static_atoms_encoder = fn token, _meta ->
      count = :counters.get(atom_counter, 1)

      if count >= @max_atoms do
        {:error, "too many unique atoms (limit: #{@max_atoms})"}
      else
        :counters.add(atom_counter, 1, 1)

        try do
          {:ok, String.to_existing_atom(token)}
        rescue
          ArgumentError -> {:ok, String.to_atom(token)}
        end
      end
    end

    case Code.string_to_quoted(source_code,
           static_atoms_encoder: static_atoms_encoder,
           columns: true
         ) do
      {:ok, ast} -> {:ok, ast}
      {:error, {_meta, message, token}} -> {:error, "parse error: #{message}#{token}"}
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

      if module_name not in @allowed_modules and not alias_of_allowed?(module_name) do
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

    if module_str in @allowed_modules or alias_of_allowed?(module_str) do
      {node, acc}
    else
      {node, ["module not allowed: #{module_str}" | acc]}
    end
  end

  # Allow everything else (literals, operators, local function calls, etc.)
  defp check_node(node, acc) do
    {node, acc}
  end

  # Check if a short module name (e.g. "Http") is the tail of an allowed
  # fully-qualified module (e.g. "Blackboex.Playgrounds.Http").
  # This lets playground code use `alias Blackboex.Playgrounds.Http` and then call `Http.get(...)`.
  defp alias_of_allowed?(short_name) do
    suffix = "." <> short_name
    Enum.any?(@allowed_modules, &String.ends_with?(&1, suffix))
  end

  defp run_sandboxed(ast) do
    task =
      Task.Supervisor.async_nolink(
        Blackboex.SandboxTaskSupervisor,
        fn ->
          Process.flag(:max_heap_size, %{size: @max_heap_size, kill: true, error_logger: false})

          try do
            {:ok, string_io} = StringIO.open("")
            original_gl = Process.group_leader()
            Process.group_leader(self(), string_io)

            {result, _bindings} = Code.eval_quoted(ast, [])

            Process.group_leader(self(), original_gl)
            {_input, io_output} = StringIO.contents(string_io)
            StringIO.close(string_io)

            result_str = inspect(result, pretty: true, limit: 1000)

            output =
              case io_output do
                "" -> result_str
                _ -> String.trim_trailing(io_output) <> "\n" <> result_str
              end

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
