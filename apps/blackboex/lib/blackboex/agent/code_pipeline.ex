defmodule Blackboex.Agent.CodePipeline do
  @moduledoc """
  Deterministic pipeline that orchestrates code generation with minimal LLM calls.

  Instead of running an LLM agent loop where the model decides each step
  (8-10 LLM calls), this pipeline calls the LLM only for creative tasks
  (generate code, fix errors) and runs mechanical steps directly in Elixir
  (format, compile, lint, run tests). Result: 2-4 LLM calls per generation.

  ## Pipeline Steps

  1. LLM generates code (streaming)
  2. Elixir formats code (Linter.auto_format)
  3. Elixir compiles code (Compiler.compile) — LLM fixes if errors (max 2 retries)
  4. Elixir lints code (Linter.run_all) — LLM fixes if issues (max 2 retries)
  5. LLM generates tests (TestGenerator)
  6. Elixir runs tests (TestRunner) — LLM fixes if failures (max 2 retries)
  7. Returns code + test_code + summary
  """

  require Logger

  alias Blackboex.Agent.FixPrompts
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.Conversations
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM.Config
  alias Blackboex.LLM.EditPrompts
  alias Blackboex.LLM.Prompts
  alias Blackboex.LLM.Templates
  alias Blackboex.LogSanitizer
  alias Blackboex.Testing.TestGenerator
  alias Blackboex.Testing.TestRunner

  @max_fix_attempts 3
  @max_total_llm_calls 15

  @type broadcast_fn :: (term() -> :ok)
  @type pipeline_opts :: [
          broadcast_fn: broadcast_fn(),
          run_id: String.t(),
          conversation_id: String.t()
        ]

  @type pipeline_result ::
          {:ok, %{code: String.t(), test_code: String.t(), summary: String.t()}}
          | {:error, String.t()}

  # ── Public API ──────────────────────────────────────────────────

  @spec run_generation(Api.t(), String.t(), pipeline_opts()) :: pipeline_result()
  def run_generation(api, description, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    reset_counters()
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    with {:ok, code} <- step_generate_code(api, description, broadcast, run_id),
         {:ok, code} <- step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <- step_generate_tests(api, code, broadcast, run_id),
         {:ok, test_code} <- step_run_and_fix_tests(api, code, test_code, broadcast, run_id),
         {:ok, doc_md} <- step_generate_docs(api, code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})

      {:ok,
       %{
         code: code,
         test_code: test_code,
         documentation_md: doc_md,
         summary: "Code generated and validated",
         usage: get_accumulated_usage()
       }}
    end
  end

  @spec run_edit(Api.t(), String.t(), String.t(), String.t(), pipeline_opts()) ::
          pipeline_result()
  def run_edit(api, instruction, current_code, current_tests, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    reset_counters()
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    with {:ok, code} <-
           step_edit_code(api, instruction, current_code, current_tests, broadcast, run_id),
         {:ok, code} <- step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <-
           step_edit_tests(api, code, instruction, current_tests, broadcast, run_id),
         {:ok, test_code} <- step_run_and_fix_tests(api, code, test_code, broadcast, run_id),
         {:ok, doc_md} <- step_generate_docs(api, code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})

      {:ok,
       %{
         code: code,
         test_code: test_code,
         documentation_md: doc_md,
         summary: "Code updated and validated",
         usage: get_accumulated_usage()
       }}
    end
  end

  # Guarded LLM call — prevents runaway loops across all fix steps.
  # Streams tokens via token_callback when available, falls back to sync.
  @spec guarded_llm_call(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp guarded_llm_call(prompt, system) do
    count = Process.get(:pipeline_llm_calls, 0)

    if count >= @max_total_llm_calls do
      {:error, "Pipeline exceeded maximum LLM calls (#{@max_total_llm_calls})"}
    else
      Process.put(:pipeline_llm_calls, count + 1)
      client = Config.client()
      token_callback = Process.get(:token_callback)

      if token_callback do
        stream_llm_call(client, prompt, system, token_callback)
      else
        sync_llm_call(client, prompt, system)
      end
    end
  end

  @spec sync_llm_call(term(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp sync_llm_call(client, prompt, system) do
    case client.generate_text(prompt, system: system) do
      {:ok, %{content: content} = result} ->
        accumulate_usage(result[:usage])
        {:ok, content}

      {:error, reason} ->
        {:error, "LLM call failed: #{LogSanitizer.sanitize(reason)}"}
    end
  end

  @spec stream_llm_call(term(), String.t(), String.t(), (String.t() -> :ok)) ::
          {:ok, String.t()} | {:error, String.t()}
  defp stream_llm_call(client, prompt, system, token_callback) do
    case client.stream_text(prompt, system: system) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        content =
          response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            token_callback.(token)
            acc <> token
          end)

        flush_stream_buffer(token_callback)
        accumulate_usage(ReqLLM.StreamResponse.usage(response))
        {:ok, content}

      {:ok, stream} ->
        content =
          Enum.reduce(stream, "", fn
            {:token, token}, acc ->
              token_callback.(token)
              acc <> token

            token, acc when is_binary(token) ->
              token_callback.(token)
              acc <> token
          end)

        flush_stream_buffer(token_callback)
        {:ok, content}

      {:error, reason} ->
        {:error, "LLM stream failed: #{LogSanitizer.sanitize(reason)}"}
    end
  rescue
    e ->
      Logger.debug("Stream failed, falling back to sync: #{Exception.message(e)}")
      run_id = Process.get(:pipeline_run_id)

      if run_id do
        Phoenix.PubSub.broadcast(Blackboex.PubSub, "run:#{run_id}", {:stream_reset, %{}})
      end

      sync_llm_call(client, prompt, system)
  end

  @spec flush_stream_buffer((String.t() -> :ok)) :: :ok
  defp flush_stream_buffer(token_callback) do
    buffer = Process.get(:stream_buffer, "")

    if buffer != "" do
      Process.put(:stream_buffer, "")
      token_callback.(buffer)
    end

    :ok
  end

  @spec reset_counters() :: term()
  defp reset_counters do
    Process.put(:pipeline_llm_calls, 0)
    Process.put(:pipeline_input_tokens, 0)
    Process.put(:pipeline_output_tokens, 0)
    Process.put(:pipeline_log, [])
  end

  # ── Rolling Context Log ────────────────────────────────────────
  # Accumulates a lightweight log of pipeline steps so fix prompts
  # can include what happened before. No extra LLM calls needed.

  @spec log_step(String.t(), :pass | :fail, String.t()) :: :ok
  defp log_step(step, status, detail) do
    entry = "[#{step}] #{status}: #{String.slice(detail, 0, 1000)}"
    log = Process.get(:pipeline_log, [])
    Process.put(:pipeline_log, log ++ [entry])
    :ok
  end

  @spec get_context_log() :: String.t()
  defp get_context_log do
    log = Process.get(:pipeline_log, [])

    case log do
      [] -> ""
      entries -> Enum.take(entries, -10) |> Enum.join("\n")
    end
  end

  @spec accumulate_usage(map() | nil) :: :ok
  defp accumulate_usage(nil), do: :ok

  defp accumulate_usage(usage) when is_map(usage) do
    input = Map.get(usage, :input_tokens, 0) || Map.get(usage, "input_tokens", 0) || 0
    output = Map.get(usage, :output_tokens, 0) || Map.get(usage, "output_tokens", 0) || 0

    Process.put(:pipeline_input_tokens, Process.get(:pipeline_input_tokens, 0) + input)
    Process.put(:pipeline_output_tokens, Process.get(:pipeline_output_tokens, 0) + output)
    :ok
  end

  @spec get_accumulated_usage() :: %{input_tokens: integer(), output_tokens: integer()}
  defp get_accumulated_usage do
    %{
      input_tokens: Process.get(:pipeline_input_tokens, 0),
      output_tokens: Process.get(:pipeline_output_tokens, 0)
    }
  end

  # ── Step 1: Generate Code ──────────────────────────────────────

  @spec step_generate_code(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_generate_code(api, description, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    touch_run(run_id)

    template_type = template_atom(api.template_type)

    system = """
    #{Prompts.system_prompt()}

    #{Templates.get(template_type)}

    Generate the handler code for this API.
    Return the code in a single ```elixir code block. No explanations outside the block.
    """

    case guarded_llm_call(description, system) do
      {:ok, content} ->
        code = extract_code(content)
        log_step("generate", :pass, "Generated #{String.length(code)} chars of handler code")
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        log_step("generate", :fail, reason)
        broadcast.({:step_failed, %{step: :generating_code, error: reason}})
        {:error, reason}
    end
  end

  # ── Step 1b: Edit Code ─────────────────────────────────────────

  @spec step_edit_code(
          Api.t(),
          String.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_edit_code(_api, instruction, current_code, _current_tests, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    touch_run(run_id)

    system = EditPrompts.system_prompt()
    prompt = EditPrompts.build_edit_prompt(current_code, instruction, [])

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        code = apply_edits_or_extract(current_code, content)
        log_step("edit_code", :pass, "Applied edit: #{String.slice(instruction, 0, 100)}")
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        log_step("edit_code", :fail, reason)
        broadcast.({:step_failed, %{step: :generating_code, error: reason}})
        {:error, reason}
    end
  end

  # ── Step 2-4: Validate and Fix ─────────────────────────────────

  @spec step_validate_and_fix(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_validate_and_fix(api, code, broadcast, run_id) do
    with {:ok, code} <- step_format(code, broadcast),
         {:ok, code} <- step_compile_with_fix(api, code, broadcast, run_id, 0),
         {:ok, code} <- step_lint_with_fix(api, code, broadcast, run_id, 0) do
      {:ok, code}
    end
  end

  @spec step_format(String.t(), broadcast_fn()) :: {:ok, String.t()}
  defp step_format(code, broadcast) do
    broadcast.({:step_started, %{step: :formatting}})

    case Linter.auto_format(code) do
      {:ok, formatted} ->
        log_step("format", :pass, "Code formatted successfully")
        broadcast.({:step_completed, %{step: :formatting, content: "Code formatted"}})
        {:ok, formatted}

      {:error, reason} ->
        log_step("format", :fail, to_string(reason))
        broadcast.({:step_failed, %{step: :formatting, error: reason}})
        # Format failure is non-fatal — proceed with unformatted code
        {:ok, code}
    end
  end

  @spec step_compile_with_fix(
          Api.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_compile_with_fix(api, code, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :compiling}})
    touch_run(run_id)

    case Compiler.compile(api, code) do
      {:ok, module} ->
        log_step("compile", :pass, "Module: #{inspect(module)}")

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
        log_step("compile", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt)

      {:error, {:compilation, reason}} ->
        error_text = inspect(reason)
        log_step("compile", :fail, error_text)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_compilation(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_compilation(_api, _code, error_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Compilation failed after #{@max_fix_attempts} fix attempts: #{error_text}"}
  end

  defp maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_compilation, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_compilation(code, error_text, get_context_log())

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        fixed_code = apply_edits_or_extract(code, content)
        log_step("fix_compile", :pass, "Fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{
             step: :fixing_compilation,
             content: "Compilation fix applied (attempt #{attempt + 1})"
           }}
        )

        with {:ok, formatted} <- step_format(fixed_code, broadcast) do
          step_compile_with_fix(api, formatted, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec step_lint_with_fix(
          Api.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_lint_with_fix(api, code, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :linting}})

    results = Linter.run_all(code)

    issues =
      results
      |> Enum.filter(&(&1.status in [:warn, :error]))
      |> Enum.flat_map(& &1.issues)

    case issues do
      [] ->
        lint_summary = format_lint_results(results)
        log_step("lint", :pass, "All checks passed")

        broadcast.({:step_completed, %{step: :linting, success: true, content: lint_summary}})

        {:ok, code}

      _issues ->
        issue_text = format_lint_results(results)
        log_step("lint", :fail, issue_text)
        broadcast.({:step_completed, %{step: :linting, success: false, content: issue_text}})
        maybe_fix_lint(api, code, issue_text, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_lint(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_lint(_api, _code, issue_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Lint issues not resolved after #{@max_fix_attempts} fix attempts: #{issue_text}"}
  end

  defp maybe_fix_lint(api, code, issue_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_lint, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_lint(code, issue_text, get_context_log())

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        fixed_code = apply_edits_or_extract(code, content)
        log_step("fix_lint", :pass, "Fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_lint, content: "Lint fix applied (attempt #{attempt + 1})"}}
        )

        with {:ok, formatted} <- step_format(fixed_code, broadcast),
             {:ok, compiled} <- step_compile_with_fix(api, formatted, broadcast, run_id, attempt) do
          step_lint_with_fix(api, compiled, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Step 5b: Edit Tests (diff-based) ────────────────────────────

  @spec step_edit_tests(
          Api.t(),
          String.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_edit_tests(api, code, instruction, current_tests, broadcast, run_id) do
    if String.trim(current_tests) == "" do
      step_generate_tests(api, code, broadcast, run_id)
    else
      broadcast.({:step_started, %{step: :generating_tests}})
      touch_run(run_id)

      system = """
      You are an expert Elixir test engineer. The handler code was just edited.
      Update the existing tests to match the code changes. Use SEARCH/REPLACE blocks.

      The edit instruction was: #{instruction}

      Rules:
      - Only change tests affected by the code edit — do NOT rewrite the whole suite.
      - If new behavior was added, ADD new test cases.
      - If behavior changed, UPDATE the relevant assertions.
      - Use SEARCH/REPLACE format (same as code edits).
      - If no test changes are needed, return: NO CHANGES NEEDED
      """

      prompt = """
      ## Current Handler Code
      ```elixir
      #{code}
      ```

      ## Current Test Code
      ```elixir
      #{current_tests}
      ```

      Return ONLY SEARCH/REPLACE blocks for the test changes needed.
      """

      case guarded_llm_call(prompt, system) do
        {:ok, content} ->
          apply_test_edits_or_skip(content, current_tests, broadcast)

        {:error, reason} ->
          log_step("edit_tests", :fail, reason)
          # Fallback to full test generation
          step_generate_tests(api, code, broadcast, run_id)
      end
    end
  end

  @spec apply_test_edits_or_skip(String.t(), String.t(), broadcast_fn()) ::
          {:ok, String.t()}
  defp apply_test_edits_or_skip(content, current_tests, broadcast) do
    if String.contains?(content, "NO CHANGES NEEDED") do
      log_step("edit_tests", :pass, "No test changes needed")
      broadcast.({:step_completed, %{step: :generating_tests, test_code: current_tests}})
      {:ok, current_tests}
    else
      test_code = apply_edits_or_extract(current_tests, content)
      log_step("edit_tests", :pass, "Tests updated via diff")
      broadcast.({:step_completed, %{step: :generating_tests, test_code: test_code}})
      {:ok, test_code}
    end
  end

  # ── Step 5: Generate Tests ─────────────────────────────────────

  @spec step_generate_tests(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_generate_tests(api, code, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_tests}})
    touch_run(run_id)

    tc = Process.get(:token_callback)
    gen_opts = if tc, do: [token_callback: tc], else: []

    case TestGenerator.generate_tests_for_code(code, api.template_type || "computation", gen_opts) do
      {:ok, %{code: test_code}} ->
        broadcast.({:step_completed, %{step: :generating_tests, test_code: test_code}})
        {:ok, test_code}

      {:error, reason} ->
        broadcast.({:step_failed, %{step: :generating_tests, error: inspect(reason)}})
        {:error, "Test generation failed: #{inspect(reason)}"}
    end
  end

  # ── Step 6: Run Tests ──────────────────────────────────────────

  @spec step_run_and_fix_tests(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_run_and_fix_tests(api, code, test_code, broadcast, run_id, attempt \\ 0) do
    broadcast.({:step_started, %{step: :running_tests}})
    touch_run(run_id)
    Process.put(:last_test_code, test_code)

    case TestRunner.run(test_code, handler_code: code) do
      {:ok, results} ->
        failed = Enum.filter(results, &(&1.status != "passed"))

        if failed == [] do
          success_text = format_test_successes(results)
          log_step("tests", :pass, "#{length(results)} tests passed")

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
          log_step("tests", :fail, failure_text)

          broadcast.(
            {:step_completed, %{step: :running_tests, success: false, content: failure_text}}
          )

          maybe_fix_tests(api, code, test_code, failure_text, broadcast, run_id, attempt)
        end

      {:error, :compile_error, message} ->
        log_step("tests", :fail, "Compile error: #{message}")

        broadcast.(
          {:step_completed,
           %{step: :running_tests, success: false, content: "Compile error: #{message}"}}
        )

        maybe_fix_tests(
          api,
          code,
          test_code,
          "Test compilation failed: #{message}",
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
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_tests(_api, _code, _test_code, failure_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Tests not passing after #{@max_fix_attempts} fix attempts: #{failure_text}"}
  end

  defp maybe_fix_tests(api, code, test_code, failure_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_tests, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_tests(code, test_code, failure_text, get_context_log())

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        apply_test_fix(api, code, content, broadcast, run_id, attempt)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec apply_test_fix(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp apply_test_fix(api, code, content, broadcast, run_id, attempt) do
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

        log_step("fix_tests", :pass, "Edit fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_tests, content: "Test fix applied (attempt #{attempt + 1})"}}
        )

        if code_edits != [] do
          revalidate_and_rerun_tests(api, fixed_code, fixed_tests, broadcast, run_id, attempt)
        else
          step_run_and_fix_tests(api, code, fixed_tests, broadcast, run_id, attempt + 1)
        end

      :error ->
        apply_legacy_test_fix(api, code, content, broadcast, run_id, attempt)
    end
  end

  @spec apply_legacy_test_fix(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp apply_legacy_test_fix(api, code, content, broadcast, run_id, attempt) do
    case FixPrompts.parse_code_and_tests(content) do
      {fixed_code, fixed_tests} ->
        log_step("fix_tests", :pass, "Full fix applied (attempt #{attempt + 1})")

        broadcast.(
          {:step_completed,
           %{step: :fixing_tests, content: "Test fix applied (attempt #{attempt + 1})"}}
        )

        revalidate_and_rerun_tests(api, fixed_code, fixed_tests, broadcast, run_id, attempt)

      :error ->
        fixed_tests = extract_code(content)
        step_run_and_fix_tests(api, code, fixed_tests, broadcast, run_id, attempt + 1)
    end
  end

  @spec revalidate_and_rerun_tests(
          Api.t(),
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp revalidate_and_rerun_tests(api, code, tests, broadcast, run_id, attempt) do
    case step_validate_and_fix(api, code, broadcast, run_id) do
      {:ok, validated_code} ->
        step_run_and_fix_tests(api, validated_code, tests, broadcast, run_id, attempt + 1)

      error ->
        error
    end
  end

  # ── Step 7: Generate Documentation ────────────────────────────

  @spec step_generate_docs(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_generate_docs(api, code, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_docs}})
    touch_run(run_id)

    doc_tc = Process.get(:token_callback)
    doc_opts = [source_code: code] ++ if(doc_tc, do: [token_callback: doc_tc], else: [])

    case DocGenerator.generate(api, doc_opts) do
      {:ok, %{doc: doc} = result} ->
        accumulate_usage(result[:usage])
        broadcast.({:step_completed, %{step: :generating_docs, content: doc}})
        {:ok, doc}

      {:error, reason} ->
        Logger.debug("Doc generation failed: #{inspect(reason)}")

        broadcast.(
          {:step_completed,
           %{step: :generating_docs, content: "Documentation generation skipped"}}
        )

        {:ok, ""}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  @spec extract_code(String.t()) :: String.t()
  defp extract_code(response) do
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
  defp apply_edits_or_extract(original_code, response) do
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
  defp code_looks_corrupted?(original, candidate) do
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

  @spec template_atom(String.t() | nil) :: :crud | :webhook | :computation
  defp template_atom("crud"), do: :crud
  defp template_atom("webhook"), do: :webhook
  defp template_atom(_), do: :computation

  @spec touch_run(String.t() | nil) :: :ok | {:ok, term()}
  defp touch_run(nil), do: :ok
  defp touch_run(run_id), do: Conversations.touch_run(run_id)
end
