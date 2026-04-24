defmodule Blackboex.Agent.Pipeline.Validation do
  @moduledoc """
  Validation and fix step functions for the code pipeline.

  Every step receives the LLM `{client, llm_opts}` context as an explicit
  parameter — the Budget module holds no global client state.
  """

  require Logger

  alias Blackboex.Agent.FixPrompts
  alias Blackboex.Agent.Pipeline.Budget
  alias Blackboex.Agent.Pipeline.CodeParser
  alias Blackboex.Agent.Pipeline.Generation
  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.DiffEngine
  alias Blackboex.CodeGen.Linter
  alias Blackboex.Testing.TestRunner

  @max_fix_attempts 3

  @type broadcast_fn :: (term() -> :ok)
  @type file_entry :: %{path: String.t(), content: String.t(), file_type: String.t()}
  @type llm_ctx :: Budget.llm_ctx()

  # ── Step 2-4: Validate and Fix ─────────────────────────────────

  @spec step_validate_and_fix(
          Api.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, String.t()} | {:error, String.t()}
  def step_validate_and_fix(api, code, llm_ctx, broadcast, run_id) do
    with {:ok, code} <- step_format(code, broadcast),
         {:ok, code} <- step_compile_with_fix(api, code, llm_ctx, broadcast, run_id, 0),
         {:ok, code} <- step_lint_with_fix(api, code, llm_ctx, broadcast, run_id, 0) do
      {:ok, code}
    end
  end

  @spec step_format(String.t(), broadcast_fn()) :: {:ok, String.t()}
  def step_format(code, broadcast) do
    broadcast.({:step_started, %{step: :formatting}})

    case Linter.auto_format(code) do
      {:ok, formatted} ->
        Budget.log_step("format", :pass, "Code formatted successfully")
        broadcast.({:step_completed, %{step: :formatting, content: "Code formatted"}})
        {:ok, formatted}

      {:error, reason} ->
        Budget.log_step("format", :fail, to_string(reason))
        broadcast.({:step_failed, %{step: :formatting, error: reason}})
        # Format failure is non-fatal — proceed with unformatted code
        {:ok, code}
    end
  end

  @spec step_compile_with_fix(
          Api.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_compile_with_fix(api, code, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :compiling}})
    Budget.touch_run(run_id)

    case Compiler.compile(api, code) do
      {:ok, module} ->
        Budget.log_step("compile", :pass, "Module: #{inspect(module)}")

        broadcast.(
          {:step_completed,
           %{
             step: :compiling,
             success: true,
             content: "Compiled successfully. Module: #{inspect(module)}"
           }}
        )

        {:ok, code}

      {:error, {:validation, errors}} ->
        error_text = Enum.join(errors, "\n")
        Budget.log_step("compile", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, llm_ctx, broadcast, run_id, attempt)

      {:error, {:compilation, reason}} ->
        error_text = inspect(reason)
        Budget.log_step("compile", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, llm_ctx, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_compilation(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_compilation(_api, _code, error_text, _llm_ctx, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Compilation failed after #{@max_fix_attempts} fix attempts: #{error_text}"}
  end

  defp maybe_fix_compilation(api, code, error_text, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_compilation, attempt: attempt + 1}})
    Budget.touch_run(run_id)

    {system, prompt} = FixPrompts.fix_compilation(code, error_text, Budget.get_context_log())

    case Budget.guarded_llm_call(llm_ctx, prompt, system) do
      {:ok, content} ->
        fixed_code = CodeParser.apply_edits_or_extract(code, content)
        Budget.log_step("fix_compile", :pass, "Fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{
             step: :fixing_compilation,
             content: "Compilation fix applied (attempt #{attempt + 1})"
           }}
        )

        with {:ok, formatted} <- step_format(fixed_code, broadcast) do
          step_compile_with_fix(api, formatted, llm_ctx, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec step_lint_with_fix(
          Api.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_lint_with_fix(api, code, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :linting}})

    results = Linter.run_all(code)

    issues =
      results
      |> Enum.filter(&(&1.status in [:warn, :error]))
      |> Enum.flat_map(& &1.issues)

    case issues do
      [] ->
        lint_summary = format_lint_results(results)
        Budget.log_step("lint", :pass, "All checks passed")

        broadcast.({:step_completed, %{step: :linting, success: true, content: lint_summary}})

        {:ok, code}

      _issues ->
        issue_text = format_lint_results(results)
        Budget.log_step("lint", :fail, issue_text)
        broadcast.({:step_completed, %{step: :linting, success: false, content: issue_text}})
        maybe_fix_lint(api, code, issue_text, llm_ctx, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_lint(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_lint(_api, _code, issue_text, _llm_ctx, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Lint issues not resolved after #{@max_fix_attempts} fix attempts: #{issue_text}"}
  end

  defp maybe_fix_lint(api, code, issue_text, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_lint, attempt: attempt + 1}})
    Budget.touch_run(run_id)

    {system, prompt} = FixPrompts.fix_lint(code, issue_text, Budget.get_context_log())

    case Budget.guarded_llm_call(llm_ctx, prompt, system) do
      {:ok, content} ->
        fixed_code = CodeParser.apply_edits_or_extract(code, content)
        Budget.log_step("fix_lint", :pass, "Fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_lint, content: "Lint fix applied (attempt #{attempt + 1})"}}
        )

        with {:ok, formatted} <- step_format(fixed_code, broadcast),
             {:ok, compiled} <-
               step_compile_with_fix(api, formatted, llm_ctx, broadcast, run_id, attempt) do
          step_lint_with_fix(api, compiled, llm_ctx, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Step 6: Run Tests ──────────────────────────────────────────

  @spec step_run_and_fix_tests(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_run_and_fix_tests(api, code, test_code, llm_ctx, broadcast, run_id, attempt \\ 0) do
    broadcast.({:step_started, %{step: :running_tests}})
    Budget.touch_run(run_id)
    Process.put(:last_test_code, test_code)

    case TestRunner.run(test_code, handler_code: code) do
      {:ok, results} ->
        failed = Enum.filter(results, &(&1.status != "passed"))

        if failed == [] do
          success_text = format_test_successes(results)
          Budget.log_step("tests", :pass, "#{length(results)} tests passed")

          broadcast.(
            {:step_completed,
             %{
               step: :running_tests,
               success: true,
               content: success_text
             }}
          )

          {:ok, test_code}
        else
          failure_text = format_test_failures(results)
          Budget.log_step("tests", :fail, failure_text)

          broadcast.(
            {:step_completed, %{step: :running_tests, success: false, content: failure_text}}
          )

          maybe_fix_tests(api, code, test_code, failure_text, llm_ctx, broadcast, run_id, attempt)
        end

      {:error, :compile_error, message} ->
        Budget.log_step("tests", :fail, "Compile error: #{message}")

        broadcast.(
          {:step_completed,
           %{step: :running_tests, success: false, content: "Compile error: #{message}"}}
        )

        maybe_fix_tests(
          api,
          code,
          test_code,
          "Test compilation failed: #{message}",
          llm_ctx,
          broadcast,
          run_id,
          attempt
        )

      {:error, :timeout} ->
        broadcast.(
          {:step_completed, %{step: :running_tests, success: false, content: "Tests timed out"}}
        )

        {:error, "Tests timed out"}

      {:error, :memory_exceeded} ->
        broadcast.(
          {:step_completed, %{step: :running_tests, success: false, content: "Memory exceeded"}}
        )

        {:error, "Tests exceeded memory limit"}
    end
  end

  @spec maybe_fix_tests(
          Api.t(),
          String.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_tests(
         _api,
         _code,
         _test_code,
         failure_text,
         _llm_ctx,
         _broadcast,
         _run_id,
         attempt
       )
       when attempt >= @max_fix_attempts do
    {:error, "Tests not passing after #{@max_fix_attempts} fix attempts: #{failure_text}"}
  end

  defp maybe_fix_tests(api, code, test_code, failure_text, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_tests, attempt: attempt + 1}})
    Budget.touch_run(run_id)

    {system, prompt} =
      FixPrompts.fix_tests(code, test_code, failure_text, Budget.get_context_log())

    case Budget.guarded_llm_call(llm_ctx, prompt, system) do
      {:ok, content} ->
        apply_test_fix(api, code, content, llm_ctx, broadcast, run_id, attempt)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec apply_test_fix(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp apply_test_fix(api, code, content, llm_ctx, broadcast, run_id, attempt) do
    case FixPrompts.parse_test_fix_edits(content) do
      {code_edits, test_edits} ->
        # Apply search/replace edits to code and tests
        fixed_code =
          case DiffEngine.apply_search_replace(code, code_edits) do
            {:ok, result} -> result
            {:error, _, _} -> code
          end

        fixed_tests =
          case DiffEngine.apply_search_replace(
                 Process.get(:last_test_code, ""),
                 test_edits
               ) do
            {:ok, result} -> result
            {:error, _, _} -> Process.get(:last_test_code, "")
          end

        Budget.log_step("fix_tests", :pass, "Edit fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_tests, content: "Test fix applied (attempt #{attempt + 1})"}}
        )

        if code_edits != [] do
          revalidate_and_rerun_tests(
            api,
            fixed_code,
            fixed_tests,
            llm_ctx,
            broadcast,
            run_id,
            attempt
          )
        else
          step_run_and_fix_tests(api, code, fixed_tests, llm_ctx, broadcast, run_id, attempt + 1)
        end

      :error ->
        apply_legacy_test_fix(api, code, content, llm_ctx, broadcast, run_id, attempt)
    end
  end

  @spec apply_legacy_test_fix(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp apply_legacy_test_fix(api, code, content, llm_ctx, broadcast, run_id, attempt) do
    case FixPrompts.parse_code_and_tests(content) do
      {fixed_code, fixed_tests} ->
        Budget.log_step("fix_tests", :pass, "Full fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_tests, content: "Test fix applied (attempt #{attempt + 1})"}}
        )

        revalidate_and_rerun_tests(
          api,
          fixed_code,
          fixed_tests,
          llm_ctx,
          broadcast,
          run_id,
          attempt
        )

      :error ->
        fixed_tests = CodeParser.extract_code(content)
        step_run_and_fix_tests(api, code, fixed_tests, llm_ctx, broadcast, run_id, attempt + 1)
    end
  end

  @spec revalidate_and_rerun_tests(
          Api.t(),
          String.t(),
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp revalidate_and_rerun_tests(api, code, tests, llm_ctx, broadcast, run_id, attempt) do
    case step_validate_and_fix(api, code, llm_ctx, broadcast, run_id) do
      {:ok, validated_code} ->
        step_run_and_fix_tests(
          api,
          validated_code,
          tests,
          llm_ctx,
          broadcast,
          run_id,
          attempt + 1
        )

      error ->
        error
    end
  end

  @spec format_test_failures([map()]) :: String.t()
  defp format_test_failures(results) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == "passed"))
    failed = total - passed

    header = "#{total} tests, #{passed} passed, #{failed} failed."

    details =
      results
      |> Enum.filter(&(&1.status != "passed"))
      |> Enum.map_join("\n", fn r ->
        error_info = if r.error, do: "\n  Error: #{r.error}", else: ""
        "FAIL: #{r.name}#{error_info}"
      end)

    "#{header}\n\n#{details}"
  end

  @spec format_test_successes([map()]) :: String.t()
  defp format_test_successes(results) do
    total = length(results)

    details =
      results
      |> Enum.map_join("\n", fn r -> "  ✓ #{r.name}" end)

    "#{details}\n\n#{total} tests, #{total} passed, 0 failed."
  end

  @spec format_lint_results([map()]) :: String.t()
  defp format_lint_results(results) do
    results
    |> Enum.map_join("\n", fn %{check: check, status: status, issues: issues} ->
      check_name = check |> to_string() |> String.capitalize()
      status_icon = if status == :pass, do: "✓", else: "✗"

      case issues do
        [] ->
          "#{status_icon} #{check_name}: pass"

        items ->
          detail = Enum.map_join(items, "\n  ", & &1)
          "#{status_icon} #{check_name}: #{status}\n  #{detail}"
      end
    end)
  end

  # ── Multi-File Validation ──────────────────────────────────────

  @spec step_validate_and_fix_files(
          Api.t(),
          [file_entry()],
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  def step_validate_and_fix_files(api, source_files, llm_ctx, broadcast, run_id) do
    # Format each file individually
    formatted_files =
      Enum.map(source_files, fn file ->
        case Linter.auto_format(file.content) do
          {:ok, formatted} -> %{file | content: formatted}
          {:error, _} -> file
        end
      end)

    # Compile all files together using compile_files/2
    broadcast.({:step_started, %{step: :compiling}})
    Budget.touch_run(run_id)

    compile_input = Enum.map(formatted_files, &%{path: &1.path, content: &1.content})

    case Compiler.compile_files(api, compile_input) do
      {:ok, module} ->
        Budget.log_step("compile_files", :pass, "Module: #{inspect(module)}")

        broadcast.(
          {:step_completed,
           %{
             step: :compiling,
             success: true,
             content: "Compiled #{length(formatted_files)} files"
           }}
        )

        # Lint each file
        lint_files(api, formatted_files, broadcast, run_id, 0)

      {:error, {:validation, errors}} ->
        error_text = Enum.join(errors, "\n")
        Budget.log_step("compile_files", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})

        maybe_fix_files_compilation(
          api,
          formatted_files,
          error_text,
          llm_ctx,
          broadcast,
          run_id,
          0
        )

      {:error, {:compilation, reason}} ->
        error_text = inspect(reason)
        Budget.log_step("compile_files", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})

        maybe_fix_files_compilation(
          api,
          formatted_files,
          error_text,
          llm_ctx,
          broadcast,
          run_id,
          0
        )
    end
  end

  @spec maybe_fix_files_compilation(
          Api.t(),
          [file_entry()],
          String.t(),
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  defp maybe_fix_files_compilation(
         _api,
         _files,
         error_text,
         _llm_ctx,
         _broadcast,
         _run_id,
         attempt
       )
       when attempt >= @max_fix_attempts do
    {:error, "Multi-file compilation failed after #{@max_fix_attempts} attempts: #{error_text}"}
  end

  defp maybe_fix_files_compilation(api, files, error_text, llm_ctx, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_compilation, attempt: attempt + 1}})
    Budget.touch_run(run_id)

    all_code =
      files
      |> Enum.map(fn f -> "### #{f.path}\n```elixir\n#{f.content}\n```" end)
      |> Enum.join("\n\n")

    system = """
    You are fixing compilation errors in a multi-file Elixir project.
    The project has #{length(files)} source files.

    Return fixes using path-annotated SEARCH/REPLACE blocks:

    <<<< /src/filename.ex
    <<<<<<< SEARCH
    (exact lines to find)
    =======
    (replacement lines)
    >>>>>>> REPLACE

    Only fix the files that have errors. Use the exact file paths shown.
    """

    prompt = """
    ## Source Files
    #{all_code}

    ## Compilation Errors
    #{error_text}

    Fix the errors using path-annotated SEARCH/REPLACE blocks.
    """

    case Budget.guarded_llm_call(llm_ctx, prompt, system) do
      {:ok, content} ->
        fixed_files = Generation.apply_path_annotated_edits(files, content)
        Budget.log_step("fix_compile_files", :pass, "Fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_compilation, content: "Fix applied (attempt #{attempt + 1})"}}
        )

        formatted = format_all_files(fixed_files)
        recompile_or_retry(api, formatted, llm_ctx, broadcast, run_id, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec format_all_files([file_entry()]) :: [file_entry()]
  defp format_all_files(files) do
    Enum.map(files, fn file ->
      case Linter.auto_format(file.content) do
        {:ok, fmt} -> %{file | content: fmt}
        {:error, _} -> file
      end
    end)
  end

  @spec recompile_or_retry(
          Api.t(),
          [file_entry()],
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, [file_entry()]} | {:error, String.t() | atom()}
  defp recompile_or_retry(api, files, llm_ctx, broadcast, run_id, attempt) do
    compile_input = Enum.map(files, &%{path: &1.path, content: &1.content})

    case Compiler.compile_files(api, compile_input) do
      {:ok, _module} ->
        lint_files(api, files, broadcast, run_id, 0)

      {:error, {:validation, errors}} ->
        maybe_fix_files_compilation(
          api,
          files,
          Enum.join(errors, "\n"),
          llm_ctx,
          broadcast,
          run_id,
          attempt
        )

      {:error, {:compilation, reason}} ->
        maybe_fix_files_compilation(
          api,
          files,
          inspect(reason),
          llm_ctx,
          broadcast,
          run_id,
          attempt
        )
    end
  end

  @spec lint_files(
          Api.t(),
          [file_entry()],
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  defp lint_files(_api, files, broadcast, _run_id, _attempt) do
    broadcast.({:step_started, %{step: :linting}})

    all_issues =
      files
      |> Enum.flat_map(fn file ->
        results = Linter.run_all(file.content)

        results
        |> Enum.filter(&(&1.status in [:warn, :error]))
        |> Enum.flat_map(fn r ->
          Enum.map(r.issues, &"#{file.path}: #{&1}")
        end)
      end)

    case all_issues do
      [] ->
        Budget.log_step("lint_files", :pass, "All files pass lint")
        broadcast.({:step_completed, %{step: :linting, success: true, content: "Lint passed"}})
        {:ok, files}

      _issues ->
        # For now, lint issues on helpers are non-fatal warnings
        issue_text = Enum.join(all_issues, "\n")
        Budget.log_step("lint_files", :pass, "Lint warnings (non-fatal): #{issue_text}")

        broadcast.(
          {:step_completed,
           %{step: :linting, success: true, content: "Lint passed with warnings"}}
        )

        {:ok, files}
    end
  end

  @spec step_run_and_fix_test_files(
          Api.t(),
          [file_entry()],
          [file_entry()],
          llm_ctx(),
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  def step_run_and_fix_test_files(api, source_files, test_files, llm_ctx, broadcast, run_id) do
    handler_code = Generation.get_handler_content(source_files)
    test_code = Enum.map_join(test_files, "\n\n", & &1.content)

    case step_run_and_fix_tests(api, handler_code, test_code, llm_ctx, broadcast, run_id) do
      {:ok, fixed_test_code} ->
        {:ok, [%{path: "/test/handler_test.ex", content: fixed_test_code, file_type: "test"}]}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
