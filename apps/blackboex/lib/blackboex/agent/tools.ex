defmodule Blackboex.Agent.Tools do
  @moduledoc """
  LangChain Function definitions for the code generation agent.

  Each tool wraps an existing BlackBoex module (Compiler, Linter, TestRunner, etc.)
  and returns results as strings that the LLM can reason about.

  Tool results always use `{:ok, string}` — even on "failure" — because the LLM
  needs to see errors as information, not as tool execution failures.
  """

  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.Linter
  alias Blackboex.Testing.TestGenerator
  alias Blackboex.Testing.TestRunner
  alias LangChain.Function

  @spec all_tools() :: [Function.t()]
  def all_tools do
    [compile_code(), format_code(), lint_code(), generate_tests(), run_tests(), submit_code()]
  end

  @spec compile_code() :: Function.t()
  def compile_code do
    Function.new!(%{
      name: "compile_code",
      description:
        "Compiles Elixir module code. Returns 'Compiled successfully' or detailed " <>
          "compilation errors with line numbers. Always compile before submitting.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Complete Elixir module source code to compile"
          }
        },
        "required" => ["code"]
      },
      function: &execute_compile/2
    })
  end

  @spec format_code() :: Function.t()
  def format_code do
    Function.new!(%{
      name: "format_code",
      description:
        "Formats Elixir code using mix format rules. Returns the formatted code " <>
          "or an error if the code has syntax issues that prevent formatting.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Elixir source code to format"
          }
        },
        "required" => ["code"]
      },
      function: &execute_format/2
    })
  end

  @spec lint_code() :: Function.t()
  def lint_code do
    Function.new!(%{
      name: "lint_code",
      description:
        "Runs Credo-style linter on Elixir code. Checks for long lines, missing " <>
          "@spec, excessive function length, and deep nesting. Returns issues or 'No issues'.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Elixir source code to lint"
          }
        },
        "required" => ["code"]
      },
      function: &execute_lint/2
    })
  end

  @spec generate_tests() :: Function.t()
  def generate_tests do
    Function.new!(%{
      name: "generate_tests",
      description:
        "Generates ExUnit test code for a handler module using a secondary LLM call. " <>
          "Returns the test code or an error. You may need to review and modify the tests.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Handler module source code to generate tests for"
          }
        },
        "required" => ["code"]
      },
      function: &execute_generate_tests/2
    })
  end

  @spec run_tests() :: Function.t()
  def run_tests do
    Function.new!(%{
      name: "run_tests",
      description:
        "Runs ExUnit tests against handler code in a sandbox. Returns test results " <>
          "with pass/fail details for each test. If tests fail, analyze whether the " <>
          "bug is in the handler code or in the test itself.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Handler module source code"
          },
          "test_code" => %{
            "type" => "string",
            "description" => "ExUnit test module source code"
          }
        },
        "required" => ["code", "test_code"]
      },
      function: &execute_run_tests/2
    })
  end

  @spec submit_code() :: Function.t()
  def submit_code do
    Function.new!(%{
      name: "submit_code",
      description:
        "Submit the final validated code, tests, and a summary of what was done. " <>
          "Only call this when code compiles, is formatted, linted, and tests pass.",
      parameters_schema: %{
        "type" => "object",
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Final handler module source code"
          },
          "test_code" => %{
            "type" => "string",
            "description" => "Final ExUnit test module source code"
          },
          "summary" => %{
            "type" => "string",
            "description" => "2-3 sentence summary of what was done and why"
          }
        },
        "required" => ["code", "test_code", "summary"]
      },
      function: &execute_submit/2
    })
  end

  # ── Tool Implementations ───────────────────────────────────────

  defp execute_compile(%{"code" => code}, context) do
    api = Map.get(context, :api)

    if is_nil(api) do
      {:ok, "Error: No API context available for compilation."}
    else
      case Compiler.compile(api, code) do
        {:ok, module} ->
          {:ok, "Compiled successfully. Module: #{inspect(module)}"}

        {:error, {:validation, errors}} ->
          formatted = Enum.map_join(errors, "\n", &"  - #{&1}")
          {:ok, "Compilation failed (validation errors):\n#{formatted}"}

        {:error, {:compilation, reason}} ->
          {:ok, "Compilation failed:\n  #{inspect(reason)}"}
      end
    end
  end

  defp execute_format(%{"code" => code}, _context) do
    case Linter.auto_format(code) do
      {:ok, formatted} ->
        {:ok, formatted}

      {:error, reason} ->
        {:ok, "Format failed: #{reason}"}
    end
  end

  defp execute_lint(%{"code" => code}, _context) do
    results = Linter.run_all(code)

    issues =
      results
      |> Enum.filter(&(&1.status in [:warn, :error]))
      |> Enum.flat_map(& &1.issues)

    case issues do
      [] ->
        {:ok, "No issues found."}

      issues ->
        formatted = Enum.map_join(issues, "\n", &"  - #{&1}")
        {:ok, "Lint issues found:\n#{formatted}"}
    end
  end

  defp execute_generate_tests(%{"code" => code}, context) do
    template_type = get_in(context, [:api, Access.key(:template_type)]) || "computation"

    case TestGenerator.generate_tests_for_code(code, template_type) do
      {:ok, %{code: test_code}} ->
        {:ok, test_code}

      {:error, reason} ->
        {:ok, "Test generation failed: #{inspect(reason)}"}
    end
  end

  defp execute_run_tests(%{"code" => code, "test_code" => test_code}, _context) do
    case TestRunner.run(test_code, handler_code: code) do
      {:ok, results} ->
        formatted = format_test_results(results)
        {:ok, formatted}

      {:error, :compile_error, message} ->
        {:ok, "Test compilation failed:\n  #{message}"}

      {:error, :timeout} ->
        {:ok, "Tests timed out (exceeded 30 seconds)."}

      {:error, :memory_exceeded} ->
        {:ok, "Tests exceeded memory limit."}
    end
  end

  defp execute_submit(%{"code" => code, "test_code" => test_code, "summary" => summary}, _ctx) do
    # submit_code is intercepted by the AgentSession — this return is for LangChain's loop
    # The actual saving is handled by the Session GenServer when it detects this tool was called
    _ = {code, test_code, summary}
    {:ok, "Code submitted successfully."}
  end

  defp format_test_results(results) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == "passed"))
    failed = total - passed

    header = "#{total} tests, #{passed} passed, #{failed} failed."

    details =
      results
      |> Enum.filter(&(&1.status != "passed"))
      |> Enum.map_join("\n", fn r ->
        error_info = if r.error, do: "\n    Error: #{r.error}", else: ""
        "  FAIL: #{r.name} (#{r.duration_ms}ms)#{error_info}"
      end)

    if details == "" do
      header
    else
      "#{header}\n\nFailures:\n#{details}"
    end
  end
end
