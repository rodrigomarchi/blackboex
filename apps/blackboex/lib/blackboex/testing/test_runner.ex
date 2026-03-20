defmodule Blackboex.Testing.TestRunner do
  @moduledoc """
  Executes ExUnit test code in an isolated process with timeout and memory limits.
  Compiles test modules, runs each test function, and captures results.
  """

  require Logger

  @default_timeout 30_000
  @max_timeout 60_000
  @max_heap_size 20_000_000
  @max_heap_cap 50_000_000
  @max_error_length 500

  @type test_result :: %{
          name: String.t(),
          status: String.t(),
          duration_ms: non_neg_integer(),
          error: String.t() | nil
        }

  @spec run(String.t(), keyword()) ::
          {:ok, [test_result()]}
          | {:error, :compile_error, String.t()}
          | {:error, :timeout}
          | {:error, :memory_exceeded}
  def run(test_code, opts \\ []) do
    case Code.string_to_quoted(test_code) do
      {:ok, _ast} ->
        execute_tests(test_code, opts)

      {:error, {_meta, message, token}} ->
        {:error, :compile_error, "#{message}#{token}"}
    end
  end

  defp execute_tests(test_code, opts) do
    timeout = opts |> Keyword.get(:timeout, @default_timeout) |> min(@max_timeout)
    max_heap = opts |> Keyword.get(:max_heap_size, @max_heap_size) |> min(@max_heap_cap)

    task =
      Task.Supervisor.async_nolink(
        Blackboex.SandboxTaskSupervisor,
        fn ->
          Process.flag(:max_heap_size, %{size: max_heap, kill: true, error_logger: true})
          run_in_process(test_code)
        end
      )

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      {:exit, :killed} ->
        {:error, :memory_exceeded}

      {:exit, reason} ->
        Logger.warning("Test runner process exited: #{inspect(reason)}")
        {:error, :compile_error, "Test execution crashed"}

      nil ->
        {:error, :timeout}
    end
  end

  defp run_in_process(test_code) do
    # Prevent auto-registration with ExUnit by replacing `use ExUnit.Case`
    # with just the assertion imports. This avoids leaking test modules
    # into the global ExUnit runner.
    safe_code = deregister_exunit(test_code)

    compiled_modules = Code.compile_string(safe_code)
    module_names = Enum.map(compiled_modules, fn {mod, _binary} -> mod end)

    # Find test functions (named "test ..." by ExUnit macro or manually)
    all_test_fns =
      Enum.flat_map(module_names, fn mod ->
        extract_test_functions(mod)
        |> Enum.map(fn fun_name -> {mod, fun_name} end)
      end)

    # Fail if no test functions found — prevents silent false positives
    if all_test_fns == [] do
      purge_modules(module_names)
      {:error, :compile_error, "No test functions found in compiled code"}
    else
      results = Enum.map(all_test_fns, fn {mod, fun_name} -> run_single_test(mod, fun_name) end)
      purge_modules(module_names)
      {:ok, results}
    end
  rescue
    e in CompileError ->
      {:error, :compile_error, Exception.message(e)}

    e ->
      Logger.warning("Test runner error: #{Exception.message(e)}")
      {:error, :compile_error, truncate_message(Exception.message(e))}
  end

  defp purge_modules(module_names) do
    for mod <- module_names do
      :code.purge(mod)
      :code.delete(mod)
    end
  end

  defp deregister_exunit(code) do
    # Replace `use ExUnit.Case` with our sandbox module that provides
    # the `test` macro and assertions without registering with ExUnit.Server
    code
    |> String.replace(
      ~r/use ExUnit\.Case\b[^\n]*/,
      "use Blackboex.Testing.SandboxCase"
    )
  end

  defp extract_test_functions(mod) do
    mod.__info__(:functions)
    |> Enum.filter(fn {name, arity} ->
      arity == 1 and String.starts_with?(Atom.to_string(name), "test ")
    end)
    |> Enum.map(fn {name, _arity} -> name end)
  end

  defp run_single_test(mod, fun_name) do
    start_time = System.monotonic_time(:microsecond)

    {status, error} =
      try do
        apply(mod, fun_name, [%{}])
        {"passed", nil}
      rescue
        e in ExUnit.AssertionError ->
          msg = format_assertion_error(e)
          {"failed", msg}

        e ->
          {"failed", truncate_message(Exception.message(e))}
      end

    elapsed = System.monotonic_time(:microsecond) - start_time

    # Convert "test some name" atom to human-readable name
    display_name =
      fun_name
      |> Atom.to_string()
      |> String.replace_prefix("test ", "")

    %{
      name: display_name,
      status: status,
      duration_ms: div(elapsed, 1000),
      error: error
    }
  end

  defp format_assertion_error(%ExUnit.AssertionError{} = err) do
    parts = []
    parts = if err.message != "Assertion failed", do: [err.message | parts], else: parts
    parts = if err.left, do: ["Expected: #{inspect(err.left)}" | parts], else: parts
    parts = if err.right, do: ["Got: #{inspect(err.right)}" | parts], else: parts
    Enum.reverse(parts) |> Enum.join("\n") |> truncate_message()
  end

  defp truncate_message(msg) when byte_size(msg) > @max_error_length do
    String.slice(msg, 0, @max_error_length) <> "..."
  end

  defp truncate_message(msg), do: msg
end
