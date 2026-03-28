defmodule Blackboex.CodeGen.UnifiedPipeline do
  @moduledoc """
  Unified code + test generation pipeline with automated validation.

  Orchestrates: code generation → formatting → compilation → linting →
  test generation → test execution, with LLM-driven fix cycles on failure.

  Three entry points:
  - `validate_and_test/3` — after initial creation, generate tests + validate all
  - `run_for_edit/5` — chat edit: generate code + tests + validate (with streaming)
  - `validate_on_save/4` — manual save: validate + re-run existing tests (no LLM retry)

  Progress and streaming callbacks allow real-time UI updates.
  """

  require Logger

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.CodeGen.UnifiedPrompts
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM.Config
  alias Blackboex.LLM.EditPrompts
  alias Blackboex.Testing.TestGenerator
  alias Blackboex.Testing.TestRunner

  @max_retries 3
  @valid_template_types %{
    "computation" => :computation,
    "crud" => :crud,
    "webhook" => :webhook
  }

  @type step ::
          :generating_code
          | :formatting
          | :compiling
          | :linting
          | :generating_tests
          | :running_tests
          | :fixing_code
          | :fixing_tests
          | :generating_docs
          | :done
          | :failed

  @type progress :: %{
          step: step(),
          attempt: non_neg_integer(),
          message: String.t()
        }

  @type validation_report :: %{
          compilation: :pass | :fail,
          compilation_errors: [String.t()],
          format: :pass | :fail,
          format_issues: [String.t()],
          credo: :pass | :fail,
          credo_issues: [String.t()],
          tests: :pass | :fail | :skipped,
          test_results: [map()],
          overall: :pass | :fail
        }

  @type result :: %{
          code: String.t(),
          test_code: String.t() | nil,
          explanation: String.t() | nil,
          documentation_md: String.t() | nil,
          validation: validation_report(),
          template: atom(),
          usage: map()
        }

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Validate existing code and generate tests. Used after initial API creation
  when code already exists from streaming generation.

  Tests are unit tests that call handler functions directly (no HTTP),
  so they can run without the API being registered in the Registry.
  """
  @spec validate_and_test(String.t(), atom(), keyword()) :: {:ok, result()} | {:error, term()}
  def validate_and_test(code, template_type, opts \\ []) do
    ctx = build_context(code, nil, template_type, opts)
    run_validation_loop(ctx, 0)
  end

  @doc """
  Generate code via chat edit, then validate and generate tests.
  Uses streaming for LLM calls.
  """
  @spec run_for_edit(Api.t(), String.t(), String.t(), [map()], keyword()) ::
          {:ok, result()} | {:error, term()}
  def run_for_edit(%Api{} = api, current_code, instruction, history, opts \\ []) do
    template_type = safe_template_atom(api.template_type)
    ctx = build_context(current_code, nil, template_type, opts)

    # Step 1: Generate code via LLM (streaming)
    notify_progress(ctx, :generating_code, 0, "Generating code changes...")

    case generate_code_streaming(current_code, instruction, history, ctx) do
      {:ok, new_code, explanation, usage} ->
        ctx = %{ctx | code: new_code, usage: merge_usage(ctx.usage, usage)}

        case run_validation_loop(ctx, 0) do
          {:ok, result} ->
            {:ok, %{result | explanation: explanation}}

          {:error, _} = error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate code via chat edit WITHOUT running validation.
  Returns the proposed code and explanation immediately for user review.
  Validation runs separately after the user accepts the change.
  """
  @spec generate_edit_only(Api.t(), String.t(), String.t(), [map()], keyword()) ::
          {:ok, %{code: String.t(), explanation: String.t(), usage: map()}} | {:error, term()}
  def generate_edit_only(%Api{} = api, current_code, instruction, history, opts \\ []) do
    template_type = safe_template_atom(api.template_type)
    ctx = build_context(current_code, nil, template_type, opts)

    notify_progress(ctx, :generating_code, 0, "Generating code changes...")

    case generate_code_streaming(current_code, instruction, history, ctx) do
      {:ok, new_code, explanation, _usage} ->
        {:ok, %{code: new_code, explanation: explanation, usage: %{}}}

      {:error, {:search_mismatch, failed_search}} ->
        # Retry: ask LLM to fix the SEARCH block
        retry_search_replace(ctx, current_code, instruction, failed_search)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry_search_replace(ctx, current_code, instruction, failed_search) do
    notify_progress(ctx, :generating_code, 1, "Retrying with corrected search...")
    client = Config.client()
    prompt = EditPrompts.build_search_retry_prompt(current_code, instruction, failed_search)
    system = EditPrompts.system_prompt()

    case client.stream_text(prompt, system: system) do
      {:ok, stream} ->
        full_response = consume_stream(stream, ctx.token_callback)

        case apply_edit_response(full_response, current_code) do
          {:ok, new_code, explanation, _} ->
            {:ok, %{code: new_code, explanation: explanation, usage: %{}}}

          {:error, _} ->
            # Final fallback: ask for complete code
            fallback_to_full_code(ctx, current_code, instruction)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fallback_to_full_code(ctx, current_code, instruction) do
    notify_progress(ctx, :generating_code, 2, "Falling back to full code generation...")
    client = Config.client()
    prompt = EditPrompts.build_edit_prompt(current_code, instruction, [])
    system = EditPrompts.fallback_system_prompt()

    case client.stream_text(prompt, system: system) do
      {:ok, stream} ->
        full_response = consume_stream(stream, ctx.token_callback)

        case EditPrompts.extract_code_block(full_response) do
          nil ->
            {:error, :no_code_found}

          code ->
            explanation = EditPrompts.extract_explanation(full_response)
            {:ok, %{code: String.trim(code), explanation: explanation, usage: %{}}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate code on manual save. Runs all checks and re-runs existing tests.
  Does NOT use LLM retry — errors are returned for the user to fix manually.
  """
  @spec validate_on_save(String.t(), String.t() | nil, atom(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def validate_on_save(code, test_code, template_type, opts \\ []) do
    ctx = build_context(code, test_code, template_type, opts)

    # Format
    notify_progress(ctx, :formatting, 0, "Formatting code...")
    {formatted_code, format_result} = do_format(code)
    ctx = %{ctx | code: formatted_code}

    # Compile
    notify_progress(ctx, :compiling, 0, "Compiling...")
    compile_result = do_compile(ctx)

    # Lint
    notify_progress(ctx, :linting, 0, "Running linters...")
    credo_result = Linter.check_credo(formatted_code)

    # Run existing tests if available
    test_results =
      if test_code && test_code != "" do
        notify_progress(ctx, :running_tests, 0, "Running tests...")

        case TestRunner.run(test_code, handler_code: formatted_code) do
          {:ok, results} -> results
          {:error, _, msg} -> [%{name: "compile", status: "failed", error: msg}]
        end
      else
        []
      end

    validation =
      build_validation_report(compile_result, format_result, credo_result, test_results)

    doc_md = generate_documentation(ctx, formatted_code)

    notify_progress(ctx, :done, 0, "Validation complete")

    {:ok,
     %{
       code: formatted_code,
       test_code: test_code,
       explanation: nil,
       documentation_md: doc_md,
       validation: validation,
       template: template_type,
       usage: %{}
     }}
  end

  # ── Validation Loop ─────────────────────────────────────────────────────

  defp run_validation_loop(_ctx, attempt) when attempt >= @max_retries do
    Logger.warning("Unified pipeline: max retries (#{@max_retries}) exceeded")
    {:error, :max_retries_exceeded}
  end

  defp run_validation_loop(ctx, attempt) do
    # Step: Format
    notify_progress(ctx, :formatting, attempt, "Formatting code...")
    {formatted_code, format_result} = do_format(ctx.code)
    ctx = %{ctx | code: formatted_code}

    # Step: Compile
    notify_progress(ctx, :compiling, attempt, "Compiling...")

    case do_compile(ctx) do
      {:ok, _module} = compile_ok ->
        handle_compilation_success(ctx, formatted_code, compile_ok, format_result, attempt)

      {:error, compile_errors} ->
        handle_compilation_failure(ctx, compile_errors, attempt)
    end
  end

  defp handle_compilation_success(ctx, formatted_code, compile_ok, format_result, attempt) do
    # Step: Lint
    notify_progress(ctx, :linting, attempt, "Running linters...")
    credo_result = Linter.check_credo(formatted_code)

    # Step: Generate tests
    notify_progress(ctx, :generating_tests, attempt, "Generating tests...")

    case generate_tests(ctx) do
      {:ok, test_code, test_usage} ->
        ctx = %{ctx | usage: merge_usage(ctx.usage, test_usage)}

        run_and_evaluate_tests(
          ctx,
          formatted_code,
          test_code,
          compile_ok,
          format_result,
          credo_result,
          attempt
        )

      {:error, _reason} ->
        build_skipped_tests_result(
          ctx,
          formatted_code,
          compile_ok,
          format_result,
          credo_result,
          attempt
        )
    end
  end

  defp run_and_evaluate_tests(
         ctx,
         formatted_code,
         test_code,
         compile_ok,
         format_result,
         credo_result,
         attempt
       ) do
    notify_progress(ctx, :running_tests, attempt, "Running tests...")

    case run_tests(test_code, ctx.code) do
      {:ok, test_results} ->
        validation =
          build_validation_report(compile_ok, format_result, credo_result, test_results)

        finalize_or_fix(
          ctx,
          formatted_code,
          test_code,
          test_results,
          validation,
          credo_result,
          attempt
        )

      {:error, test_error} ->
        handle_test_error(ctx, formatted_code, test_code, test_error, attempt)
    end
  end

  defp finalize_or_fix(
         ctx,
         formatted_code,
         test_code,
         test_results,
         validation,
         credo_result,
         attempt
       ) do
    if validation.overall == :pass do
      notify_progress(ctx, :done, attempt, "All validations passed")
      build_success_result(ctx, formatted_code, test_code, validation)
    else
      handle_test_failures(ctx, formatted_code, test_code, test_results, credo_result, attempt)
    end
  end

  defp build_success_result(ctx, code, test_code, validation) do
    doc_md = generate_documentation(ctx, code)

    {:ok,
     %{
       code: code,
       test_code: test_code,
       explanation: nil,
       documentation_md: doc_md,
       validation: validation,
       template: ctx.template_type,
       usage: ctx.usage
     }}
  end

  defp build_skipped_tests_result(
         ctx,
         formatted_code,
         compile_ok,
         format_result,
         credo_result,
         attempt
       ) do
    validation = build_validation_report(compile_ok, format_result, credo_result, [])
    notify_progress(ctx, :done, attempt, "Tests could not be generated")

    {:ok,
     %{
       code: formatted_code,
       test_code: nil,
       explanation: nil,
       validation: %{validation | tests: :skipped},
       template: ctx.template_type,
       usage: ctx.usage
     }}
  end

  defp handle_compilation_failure(ctx, compile_errors, attempt) do
    notify_progress(ctx, :fixing_code, attempt, "Fixing compilation errors...")

    case fix_code(ctx, compile_errors) do
      {:ok, fixed_code, usage} ->
        ctx = %{ctx | code: fixed_code, usage: merge_usage(ctx.usage, usage)}
        run_validation_loop(ctx, attempt + 1)

      {:error, _reason} ->
        {:error, :compilation_failed}
    end
  end

  # ── Code Generation (Streaming) ────────────────────────────────────────

  defp generate_code_streaming(current_code, instruction, history, ctx) do
    client = Config.client()
    prompt = EditPrompts.build_edit_prompt(current_code, instruction, history)
    system = EditPrompts.system_prompt()

    case client.stream_text(prompt, system: system) do
      {:ok, stream} ->
        full_response = consume_stream(stream, ctx.token_callback)
        apply_edit_response(full_response, current_code)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_edit_response(full_response, current_code) do
    case EditPrompts.parse_response(full_response) do
      {:ok, :search_replace, blocks, explanation} ->
        case DiffEngine.apply_search_replace(current_code, blocks) do
          {:ok, new_code} -> {:ok, new_code, explanation, %{}}
          {:error, :search_not_found, failed} -> {:error, {:search_mismatch, failed}}
        end

      {:ok, :full_code, code, explanation} ->
        {:ok, code, explanation, %{}}

      {:error, :no_changes_found} ->
        {:error, :no_changes_found}
    end
  end

  # ── Test Generation ────────────────────────────────────────────────────

  defp generate_tests(ctx) do
    template = to_string(ctx.template_type)
    opts = if ctx[:test_token_callback], do: [token_callback: ctx.test_token_callback], else: []

    case TestGenerator.generate_tests_for_code(ctx.code, template, opts) do
      {:ok, %{code: test_code, usage: usage}} -> {:ok, test_code, usage}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Documentation Generation ──────────────────────────────────────────

  defp generate_documentation(ctx, code) do
    notify_progress(ctx, :generating_docs, 0, "Generating documentation...")

    api = %Api{
      id: Ecto.UUID.generate(),
      name: "API",
      slug: "api",
      description: "",
      source_code: code,
      template_type: to_string(ctx.template_type),
      method: "POST",
      requires_auth: true,
      organization_id: Ecto.UUID.generate(),
      user_id: 0
    }

    opts =
      if ctx[:doc_token_callback],
        do: [token_callback: ctx.doc_token_callback],
        else: []

    case DocGenerator.generate(api, opts) do
      {:ok, %{doc: doc}} -> doc
      {:error, _reason} -> nil
    end
  end

  defp run_tests(test_code, handler_code) do
    case TestRunner.run(test_code, handler_code: handler_code) do
      {:ok, results} ->
        {:ok, results}

      {:error, :compile_error, msg} ->
        {:error, {:compile_error, msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Fix Cycle ──────────────────────────────────────────────────────────

  defp handle_test_failures(ctx, code, test_code, test_results, _credo_result, attempt) do
    failed = Enum.filter(test_results, &(&1.status == "failed"))
    errors = format_test_errors(failed)

    if length(failed) == length(test_results) do
      fix_code_after_total_failure(ctx, errors, attempt)
    else
      fix_tests_after_partial_failure(ctx, code, test_code, errors, attempt)
    end
  end

  defp format_test_errors(failed) do
    Enum.map(failed, fn r -> "Test '#{r.name}' failed: #{r.error || "unknown"}" end)
  end

  defp fix_code_after_total_failure(ctx, errors, attempt) do
    notify_progress(ctx, :fixing_code, attempt, "All tests failed, fixing code...")

    case fix_code(ctx, errors) do
      {:ok, fixed_code, usage} ->
        ctx = %{ctx | code: fixed_code, usage: merge_usage(ctx.usage, usage)}
        run_validation_loop(ctx, attempt + 1)

      {:error, _} ->
        {:error, :fix_failed}
    end
  end

  defp fix_tests_after_partial_failure(ctx, code, test_code, errors, attempt) do
    notify_progress(ctx, :fixing_tests, attempt, "Fixing failing tests...")

    case fix_tests(ctx, test_code, errors, code) do
      {:ok, fixed_test_code, usage} ->
        ctx = %{ctx | usage: merge_usage(ctx.usage, usage)}
        evaluate_fixed_tests(ctx, code, fixed_test_code, attempt)

      {:error, _} ->
        run_validation_loop(ctx, attempt + 1)
    end
  end

  defp evaluate_fixed_tests(ctx, code, fixed_test_code, attempt) do
    case run_tests(fixed_test_code, code) do
      {:ok, new_results} ->
        if Enum.all?(new_results, &(&1.status == "passed")) do
          build_fixed_tests_result(ctx, code, fixed_test_code, new_results, attempt)
        else
          run_validation_loop(ctx, attempt + 1)
        end

      {:error, _} ->
        run_validation_loop(ctx, attempt + 1)
    end
  end

  defp build_fixed_tests_result(ctx, code, fixed_test_code, new_results, attempt) do
    format_result = Linter.check_format(code)
    credo_result = Linter.check_credo(code)
    validation = build_validation_report({:ok, nil}, format_result, credo_result, new_results)

    notify_progress(ctx, :done, attempt, "All validations passed")
    build_success_result(ctx, code, fixed_test_code, validation)
  end

  defp handle_test_error(ctx, _code, _test_code, error, attempt) do
    error_msg =
      case error do
        {:compile_error, msg} -> msg
        other -> inspect(other)
      end

    notify_progress(ctx, :fixing_tests, attempt, "Test compilation error, regenerating...")
    Logger.info("Test error in pipeline: #{error_msg}, retrying (attempt #{attempt + 1})")
    run_validation_loop(ctx, attempt + 1)
  end

  defp fix_code(ctx, errors) do
    prompt = UnifiedPrompts.build_fix_code_prompt(ctx.code, errors)
    stream_and_parse_fix(prompt, ctx.token_callback)
  end

  defp fix_tests(ctx, test_code, errors, handler_code) do
    prompt = UnifiedPrompts.build_fix_test_prompt(test_code, errors, handler_code)
    stream_and_parse_fix(prompt, ctx.token_callback)
  end

  defp stream_and_parse_fix(prompt, token_callback) do
    client = Config.client()
    system = EditPrompts.system_prompt()

    case client.stream_text(prompt, system: system) do
      {:ok, stream} ->
        full_response = consume_stream(stream, token_callback)

        case UnifiedPrompts.parse_response(full_response) do
          {:ok, fixed_code} -> {:ok, fixed_code, %{}}
          {:error, :no_code_found} -> {:error, :no_code_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Compilation ────────────────────────────────────────────────────────

  defp do_compile(ctx) do
    api_stub = %Api{
      id: Ecto.UUID.generate(),
      template_type: to_string(ctx.template_type)
    }

    case Compiler.compile(api_stub, ctx.code) do
      {:ok, module} -> {:ok, module}
      {:error, {:validation, reasons}} -> {:error, reasons}
      {:error, {:compilation, reason}} -> {:error, [reason]}
    end
  end

  # ── Formatting ─────────────────────────────────────────────────────────

  defp do_format(code) do
    case Linter.auto_format(code) do
      {:ok, formatted} ->
        format_check =
          if formatted == code do
            %{check: :format, status: :pass, issues: []}
          else
            %{check: :format, status: :warn, issues: ["Code was auto-formatted"]}
          end

        {formatted, format_check}

      {:error, _reason} ->
        {code, %{check: :format, status: :error, issues: ["Code has syntax errors"]}}
    end
  end

  # ── Validation Report ──────────────────────────────────────────────────

  defp build_validation_report(compile_result, format_result, credo_result, test_results) do
    compilation_pass = match?({:ok, _}, compile_result)
    format_pass = format_result.status in [:pass, :warn]
    credo_pass = credo_result.status in [:pass, :warn]
    tests_status = evaluate_tests_status(test_results)

    %{
      compilation: pass_or_fail(compilation_pass),
      compilation_errors: extract_compile_errors(compile_result, compilation_pass),
      format: pass_or_fail(format_pass),
      format_issues: format_result.issues,
      credo: pass_or_fail(credo_pass),
      credo_issues: credo_result.issues,
      tests: tests_status,
      test_results: test_results,
      overall: compute_overall(compilation_pass, format_pass, credo_pass, tests_status)
    }
  end

  defp evaluate_tests_status([]), do: :skipped

  defp evaluate_tests_status(test_results) do
    if Enum.all?(test_results, &(&1.status == "passed")), do: :pass, else: :fail
  end

  defp extract_compile_errors(_result, true), do: []
  defp extract_compile_errors(result, false), do: elem(result, 1)

  defp pass_or_fail(true), do: :pass
  defp pass_or_fail(false), do: :fail

  defp compute_overall(compilation_pass, format_pass, credo_pass, tests_status) do
    if compilation_pass and format_pass and credo_pass and tests_status in [:pass, :skipped] do
      :pass
    else
      :fail
    end
  end

  # ── Context & Helpers ──────────────────────────────────────────────────

  defp build_context(code, test_code, template_type, opts) do
    %{
      code: code,
      test_code: test_code,
      template_type: template_type,
      progress_callback: Keyword.get(opts, :progress_callback),
      token_callback: Keyword.get(opts, :token_callback),
      test_token_callback: Keyword.get(opts, :test_token_callback),
      doc_token_callback: Keyword.get(opts, :doc_token_callback),
      usage: %{}
    }
  end

  defp notify_progress(%{progress_callback: nil}, _step, _attempt, _msg), do: :ok

  defp notify_progress(%{progress_callback: callback}, step, attempt, message) do
    callback.(%{step: step, attempt: attempt, message: message})
  end

  defp consume_stream(%ReqLLM.StreamResponse{} = response, token_callback) do
    response
    |> ReqLLM.StreamResponse.tokens()
    |> Enum.reduce("", fn token, acc ->
      if token_callback, do: token_callback.(token)
      acc <> token
    end)
  end

  # Fallback for mock/test streams returning plain enumerables
  defp consume_stream(stream, token_callback) when is_list(stream) do
    Enum.reduce(stream, "", fn {:token, token}, acc ->
      if token_callback, do: token_callback.(token)
      acc <> token
    end)
  end

  defp merge_usage(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _k, v1, v2 ->
      if is_number(v1) and is_number(v2), do: v1 + v2, else: v2
    end)
  end

  defp merge_usage(a, _b), do: a

  defp safe_template_atom(type) when is_binary(type) do
    Map.get(@valid_template_types, type) ||
      raise ArgumentError, "invalid template type: #{inspect(type)}"
  end

  defp safe_template_atom(type) when is_atom(type), do: type
end
