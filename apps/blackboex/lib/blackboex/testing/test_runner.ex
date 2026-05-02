defmodule Blackboex.Testing.TestRunner do
  @moduledoc """
  Executes ExUnit test code in an isolated process with timeout and memory limits.

  When `handler_code` is provided, it is compiled into a `Handler` module before
  the tests run, so tests can call `Handler.handle(params)` directly without
  duplicating the handler source code.
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

  @spec run_files(
          [%{path: String.t(), content: String.t()}],
          [%{path: String.t(), content: String.t()}],
          keyword()
        ) ::
          {:ok, [test_result()]}
          | {:error, :compile_error, String.t()}
          | {:error, :timeout}
          | {:error, :memory_exceeded}
  def run_files(test_files, source_files, opts \\ [])
      when is_list(test_files) and is_list(source_files) do
    handler_code = Enum.map_join(source_files, "\n\n", &(&1.content || &1[:content] || ""))
    test_code = Enum.map_join(test_files, "\n\n", &(&1.content || &1[:content] || ""))

    run(test_code, Keyword.put(opts, :handler_code, handler_code))
  end

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
    handler_code = Keyword.get(opts, :handler_code)

    task =
      Task.Supervisor.async_nolink(
        Blackboex.SandboxTaskSupervisor,
        fn ->
          Process.flag(:max_heap_size, %{size: max_heap, kill: true, error_logger: true})
          run_in_process(test_code, handler_code)
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

  defp run_in_process(test_code, handler_code) do
    # Compile handler code into a uniquely-named module to avoid conflicts
    # when multiple tests run in parallel. Replace references in test_code.
    unique_id = System.unique_integer([:positive])
    handler_modules = compile_handler_module(handler_code, unique_id)

    # Prevent auto-registration with ExUnit
    safe_code =
      test_code
      |> String.replace("Handler.", "Handler_#{unique_id}.")
      |> String.replace("defmodule HandlerTest", "defmodule HandlerTest_#{unique_id}")
      |> deregister_exunit()

    # User test code may define helper modules (Helpers, Response, Request)
    # that collide with names from other compiled tests; suppress the noisy
    # "redefining module" warnings while we recompile.
    compiled_modules = with_ignore_module_conflict(fn -> Code.compile_string(safe_code) end)
    module_names = Enum.map(compiled_modules, fn {mod, _binary} -> mod end)

    all_test_fns =
      Enum.flat_map(module_names, fn mod ->
        extract_test_functions(mod)
        |> Enum.map(fn fun_name -> {mod, fun_name} end)
      end)

    if all_test_fns == [] do
      purge_modules(module_names ++ handler_modules)
      {:error, :compile_error, "No test functions found in compiled code"}
    else
      results = Enum.map(all_test_fns, fn {mod, fun_name} -> run_single_test(mod, fun_name) end)
      purge_modules(module_names ++ handler_modules)
      {:ok, results}
    end
  rescue
    e in CompileError ->
      {:error, :compile_error, Exception.message(e)}

    e ->
      Logger.warning("Test runner error: #{Exception.message(e)}")
      {:error, :compile_error, truncate_message(Exception.message(e))}
  end

  defp compile_handler_module(nil, _unique_id), do: []

  defp compile_handler_module(handler_code, unique_id) do
    module_code = """
    defmodule Handler_#{unique_id} do
      #{handler_code}
    end
    """

    compiled = with_ignore_module_conflict(fn -> Code.compile_string(module_code) end)
    Enum.map(compiled, fn {mod, _binary} -> mod end)
  rescue
    e ->
      Logger.warning("Failed to compile Handler module: #{Exception.message(e)}")
      []
  end

  defp with_ignore_module_conflict(fun) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      fun.()
    after
      Code.put_compiler_option(:ignore_module_conflict, previous || false)
    end
  end

  defp purge_modules(module_names) do
    for mod <- module_names do
      :code.purge(mod)
      :code.delete(mod)
    end
  end

  defp deregister_exunit(code) do
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
