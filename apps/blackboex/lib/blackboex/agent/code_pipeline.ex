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
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.Conversations
  alias Blackboex.LLM.Config
  alias Blackboex.LLM.Prompts
  alias Blackboex.LLM.Templates
  alias Blackboex.Testing.TestGenerator
  alias Blackboex.Testing.TestRunner

  @max_fix_attempts 2
  @max_total_llm_calls 8

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
    reset_llm_counter()

    with {:ok, code} <- step_generate_code(api, description, broadcast, run_id),
         {:ok, code} <- step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <- step_generate_tests(api, code, broadcast, run_id),
         {:ok, test_code} <- step_run_and_fix_tests(api, code, test_code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})
      {:ok, %{code: code, test_code: test_code, summary: "Code generated and validated"}}
    end
  end

  @spec run_edit(Api.t(), String.t(), String.t(), String.t(), pipeline_opts()) :: pipeline_result()
  def run_edit(api, instruction, current_code, current_tests, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    reset_llm_counter()

    with {:ok, code} <- step_edit_code(api, instruction, current_code, current_tests, broadcast, run_id),
         {:ok, code} <- step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <- step_generate_tests(api, code, broadcast, run_id),
         {:ok, test_code} <- step_run_and_fix_tests(api, code, test_code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})
      {:ok, %{code: code, test_code: test_code, summary: "Code updated and validated"}}
    end
  end

  # Guarded LLM call — prevents runaway loops across all fix steps
  @spec guarded_llm_call(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp guarded_llm_call(prompt, system) do
    count = Process.get(:pipeline_llm_calls, 0)

    if count >= @max_total_llm_calls do
      {:error, "Pipeline exceeded maximum LLM calls (#{@max_total_llm_calls})"}
    else
      Process.put(:pipeline_llm_calls, count + 1)
      client = Config.client()

      case client.generate_text(prompt, system: system) do
        {:ok, %{content: content}} -> {:ok, content}
        {:error, reason} -> {:error, "LLM call failed: #{inspect(reason)}"}
      end
    end
  end

  @spec reset_llm_counter() :: term()
  defp reset_llm_counter, do: Process.put(:pipeline_llm_calls, 0)

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

    Generate the handler code for this API. Return ONLY the code, no explanations.
    Do not wrap in markdown fences.
    Keep functions under 20 lines. Extract helpers for validation and error formatting.
    """

    case guarded_llm_call(description, system) do
      {:ok, content} ->
        code = extract_code(content)
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        broadcast.({:step_failed, %{step: :generating_code, error: reason}})
        {:error, reason}
    end
  end

  # ── Step 1b: Edit Code ─────────────────────────────────────────

  @spec step_edit_code(Api.t(), String.t(), String.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_edit_code(api, instruction, current_code, current_tests, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    touch_run(run_id)

    template_type = template_atom(api.template_type)
    base_prompt = "#{Prompts.system_prompt()}\n\n#{Templates.get(template_type)}"
    {system, prompt} = FixPrompts.edit_code(base_prompt, instruction, current_code, current_tests)

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        code = extract_code(content)
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
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
        broadcast.({:step_completed, %{step: :formatting, code: formatted}})
        {:ok, formatted}

      {:error, reason} ->
        broadcast.({:step_failed, %{step: :formatting, error: reason}})
        # Format failure is non-fatal — proceed with unformatted code
        {:ok, code}
    end
  end

  @spec step_compile_with_fix(Api.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_compile_with_fix(api, code, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :compiling}})
    touch_run(run_id)

    case Compiler.compile(api, code) do
      {:ok, _module} ->
        broadcast.({:step_completed, %{step: :compiling, success: true, content: "Compiled successfully"}})
        {:ok, code}

      {:error, {:validation, errors}} ->
        error_text = Enum.join(errors, "\n")
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt)

      {:error, {:compilation, reason}} ->
        error_text = inspect(reason)
        broadcast.({:step_completed, %{step: :compiling, success: false, content: error_text}})
        maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_compilation(Api.t(), String.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_compilation(_api, _code, error_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Compilation failed after #{@max_fix_attempts} fix attempts: #{error_text}"}
  end

  defp maybe_fix_compilation(api, code, error_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_compilation, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_compilation(code, error_text)

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        fixed_code = extract_code(content)
        broadcast.({:step_completed, %{step: :fixing_compilation, code: fixed_code}})

        with {:ok, formatted} <- step_format(fixed_code, broadcast) do
          step_compile_with_fix(api, formatted, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec step_lint_with_fix(Api.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
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
        broadcast.({:step_completed, %{step: :linting, success: true, content: "No issues found"}})
        {:ok, code}

      issues ->
        issue_text = Enum.join(issues, "\n")
        broadcast.({:step_completed, %{step: :linting, success: false, content: issue_text}})
        maybe_fix_lint(api, code, issue_text, broadcast, run_id, attempt)
    end
  end

  @spec maybe_fix_lint(Api.t(), String.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_lint(_api, _code, issue_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Lint issues not resolved after #{@max_fix_attempts} fix attempts: #{issue_text}"}
  end

  defp maybe_fix_lint(api, code, issue_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_lint, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_lint(code, issue_text)

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        fixed_code = extract_code(content)
        broadcast.({:step_completed, %{step: :fixing_lint, code: fixed_code}})

        with {:ok, formatted} <- step_format(fixed_code, broadcast),
             {:ok, compiled} <- step_compile_with_fix(api, formatted, broadcast, run_id, 0) do
          step_lint_with_fix(api, compiled, broadcast, run_id, attempt + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Step 5: Generate Tests ─────────────────────────────────────

  @spec step_generate_tests(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_generate_tests(api, code, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_tests}})
    touch_run(run_id)

    case TestGenerator.generate_tests_for_code(code, api.template_type || "computation") do
      {:ok, %{code: test_code}} ->
        broadcast.({:step_completed, %{step: :generating_tests, test_code: test_code}})
        {:ok, test_code}

      {:error, reason} ->
        broadcast.({:step_failed, %{step: :generating_tests, error: inspect(reason)}})
        {:error, "Test generation failed: #{inspect(reason)}"}
    end
  end

  # ── Step 6: Run Tests ──────────────────────────────────────────

  @spec step_run_and_fix_tests(Api.t(), String.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp step_run_and_fix_tests(api, code, test_code, broadcast, run_id, attempt \\ 0) do
    broadcast.({:step_started, %{step: :running_tests}})
    touch_run(run_id)

    case TestRunner.run(test_code, handler_code: code) do
      {:ok, results} ->
        failed = Enum.filter(results, &(&1.status != "passed"))
        total = length(results)
        passed = total - length(failed)

        if failed == [] do
          broadcast.({:step_completed, %{step: :running_tests, success: true, content: "#{total} tests, #{passed} passed, 0 failed."}})
          {:ok, test_code}
        else
          failure_text = format_test_failures(results)
          broadcast.({:step_completed, %{step: :running_tests, success: false, content: failure_text}})
          maybe_fix_tests(api, code, test_code, failure_text, broadcast, run_id, attempt)
        end

      {:error, :compile_error, message} ->
        broadcast.({:step_completed, %{step: :running_tests, success: false, content: "Compile error: #{message}"}})
        maybe_fix_tests(api, code, test_code, "Test compilation failed: #{message}", broadcast, run_id, attempt)

      {:error, :timeout} ->
        broadcast.({:step_completed, %{step: :running_tests, success: false, content: "Tests timed out"}})
        {:error, "Tests timed out"}

      {:error, :memory_exceeded} ->
        broadcast.({:step_completed, %{step: :running_tests, success: false, content: "Memory exceeded"}})
        {:error, "Tests exceeded memory limit"}
    end
  end

  @spec maybe_fix_tests(
          Api.t(), String.t(), String.t(), String.t(),
          broadcast_fn(), String.t() | nil, non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp maybe_fix_tests(_api, _code, _test_code, failure_text, _broadcast, _run_id, attempt)
       when attempt >= @max_fix_attempts do
    {:error, "Tests not passing after #{@max_fix_attempts} fix attempts: #{failure_text}"}
  end

  defp maybe_fix_tests(api, code, test_code, failure_text, broadcast, run_id, attempt) do
    broadcast.({:step_started, %{step: :fixing_tests, attempt: attempt + 1}})
    touch_run(run_id)

    {system, prompt} = FixPrompts.fix_tests(code, test_code, failure_text)

    case guarded_llm_call(prompt, system) do
      {:ok, content} ->
        apply_test_fix(api, code, content, broadcast, run_id, attempt)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec apply_test_fix(Api.t(), String.t(), String.t(), broadcast_fn(), String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp apply_test_fix(api, code, content, broadcast, run_id, attempt) do
    case FixPrompts.parse_code_and_tests(content) do
      {fixed_code, fixed_tests} ->
        broadcast.({:step_completed, %{step: :fixing_tests, code: fixed_code, test_code: fixed_tests}})
        revalidate_and_rerun_tests(api, fixed_code, fixed_tests, broadcast, run_id, attempt)

      :error ->
        fixed_tests = extract_code(content)
        step_run_and_fix_tests(api, code, fixed_tests, broadcast, run_id, attempt + 1)
    end
  end

  @spec revalidate_and_rerun_tests(
          Api.t(), String.t(), String.t(),
          broadcast_fn(), String.t() | nil, non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp revalidate_and_rerun_tests(api, code, tests, broadcast, run_id, attempt) do
    case step_validate_and_fix(api, code, broadcast, run_id) do
      {:ok, validated_code} ->
        step_run_and_fix_tests(api, validated_code, tests, broadcast, run_id, attempt + 1)

      error ->
        error
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

  @spec template_atom(String.t() | nil) :: :crud | :webhook | :computation
  defp template_atom("crud"), do: :crud
  defp template_atom("webhook"), do: :webhook
  defp template_atom(_), do: :computation

  @spec touch_run(String.t() | nil) :: :ok | {:ok, term()}
  defp touch_run(nil), do: :ok
  defp touch_run(run_id), do: Conversations.touch_run(run_id)
end
