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

  alias Blackboex.Agent.Pipeline.Budget
  alias Blackboex.Agent.Pipeline.Generation
  alias Blackboex.Agent.Pipeline.Validation
  alias Blackboex.Apis.Api
  alias Blackboex.LLM.Prompts
  alias Blackboex.LLM.Templates

  @max_total_llm_calls 15

  @type broadcast_fn :: (term() -> :ok)
  @type pipeline_opts :: [
          broadcast_fn: broadcast_fn(),
          run_id: String.t(),
          conversation_id: String.t(),
          token_callback: (String.t() -> :ok) | nil,
          max_llm_calls: pos_integer() | nil
        ]

  @type file_entry :: %{path: String.t(), content: String.t(), file_type: String.t()}

  @type pipeline_result ::
          {:ok,
           %{
             code: String.t(),
             test_code: String.t(),
             files: [file_entry()],
             test_files: [file_entry()],
             documentation_md: String.t(),
             summary: String.t(),
             usage: map()
           }}
          | {:error, String.t() | atom()}

  # ── Public API ──────────────────────────────────────────────────

  @spec run_generation(Api.t(), String.t(), pipeline_opts()) :: pipeline_result()
  def run_generation(api, description, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    Budget.reset_counters()
    max_calls = opts[:max_llm_calls] || @max_total_llm_calls
    Process.put(:pipeline_max_llm_calls, max_calls)
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    with {:ok, code} <- Generation.step_generate_code(api, description, broadcast, run_id),
         {:ok, code} <- Validation.step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <- Generation.step_generate_tests(api, code, broadcast, run_id),
         {:ok, test_code} <-
           Validation.step_run_and_fix_tests(api, code, test_code, broadcast, run_id),
         {:ok, doc_md} <- Generation.step_generate_docs(api, code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})

      {:ok,
       %{
         code: code,
         test_code: test_code,
         documentation_md: doc_md,
         summary: "Code generated and validated",
         usage: Budget.get_accumulated_usage()
       }}
    end
  end

  # ── Multi-File Generation ────────────────────────────────────

  @spec run_multi_file_generation(Api.t(), String.t(), pipeline_opts()) :: pipeline_result()
  def run_multi_file_generation(api, description, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    Budget.reset_counters()
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    saved_callback = Process.get(:token_callback)

    result =
      with {:ok, manifest} <- step_plan_files(api, description, broadcast, run_id),
           :ok <- Budget.set_dynamic_budget(manifest, opts),
           {:ok, handler_code} <-
             Generation.step_generate_handler(api, description, manifest, broadcast, run_id),
           :ok <- Budget.save_partial(:handler, handler_code),
           {:ok, helper_files} <-
             Generation.step_generate_helpers(
               api,
               description,
               handler_code,
               manifest,
               broadcast,
               run_id
             ),
           source_files <- Generation.build_source_files(handler_code, helper_files),
           :ok <- Budget.save_partial(:source_files, source_files),
           # Disable streaming for validation/fix phases — fixes must not appear in editor
           :ok <- Budget.disable_streaming(),
           {:ok, source_files} <-
             Validation.step_validate_and_fix_files(api, source_files, broadcast, run_id),
           :ok <- Budget.save_partial(:source_files, source_files),
           # Re-enable streaming for test generation
           :ok <- Budget.restore_streaming(saved_callback),
           {:ok, test_files} <-
             Generation.step_generate_test_files(api, source_files, broadcast, run_id),
           # Disable streaming for test fix phase
           :ok <- Budget.disable_streaming(),
           {:ok, test_files} <-
             Validation.step_run_and_fix_test_files(
               api,
               source_files,
               test_files,
               broadcast,
               run_id
             ),
           :ok <- Budget.restore_streaming(saved_callback),
           {:ok, doc_md} <-
             Generation.step_generate_docs(
               api,
               Generation.get_handler_content(source_files),
               broadcast,
               run_id
             ) do
        broadcast.({:step_completed, %{step: :submitting}})
        handler_code = Generation.get_handler_content(source_files)

        {:ok,
         %{
           code: handler_code,
           test_code: Enum.map_join(test_files, "\n\n", & &1.content),
           files: source_files,
           test_files: test_files,
           documentation_md: doc_md,
           summary: "Multi-file code generated and validated",
           usage: Budget.get_accumulated_usage()
         }}
      end

    case result do
      {:error, :budget_exhausted} -> Budget.build_partial_result()
      other -> other
    end
  end

  # ── Multi-File Edit ────────────────────────────────────────────

  @spec run_multi_file_edit(Api.t(), String.t(), [file_entry()], [file_entry()], pipeline_opts()) ::
          pipeline_result()
  def run_multi_file_edit(api, instruction, current_files, current_test_files, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    Budget.reset_counters()
    max_calls = opts[:max_llm_calls] || @max_total_llm_calls
    Process.put(:pipeline_max_llm_calls, max_calls)
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    with {:ok, edited_files} <-
           Generation.step_edit_files(api, instruction, current_files, broadcast, run_id),
         {:ok, edited_files} <-
           Validation.step_validate_and_fix_files(api, edited_files, broadcast, run_id),
         handler_code <- Generation.get_handler_content(edited_files),
         current_test_code <- Enum.map_join(current_test_files, "\n\n", & &1.content),
         {:ok, test_code} <-
           Generation.step_edit_tests(
             api,
             handler_code,
             instruction,
             current_test_code,
             broadcast,
             run_id
           ),
         {:ok, test_code} <-
           Validation.step_run_and_fix_tests(api, handler_code, test_code, broadcast, run_id),
         {:ok, doc_md} <- Generation.step_generate_docs(api, handler_code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})

      test_files = [
        %{path: "/test/handler_test.ex", content: test_code, file_type: "test"}
      ]

      {:ok,
       %{
         code: handler_code,
         test_code: test_code,
         files: edited_files,
         test_files: test_files,
         documentation_md: doc_md,
         summary: "Multi-file code updated and validated",
         usage: Budget.get_accumulated_usage()
       }}
    end
  end

  @spec run_edit(Api.t(), String.t(), String.t(), String.t(), pipeline_opts()) ::
          pipeline_result()
  def run_edit(api, instruction, current_code, current_tests, opts \\ []) do
    broadcast = opts[:broadcast_fn] || fn _ -> :ok end
    run_id = opts[:run_id]
    Budget.reset_counters()
    max_calls = opts[:max_llm_calls] || @max_total_llm_calls
    Process.put(:pipeline_max_llm_calls, max_calls)
    Process.put(:pipeline_run_id, run_id)
    Process.put(:token_callback, opts[:token_callback])

    with {:ok, code} <-
           Generation.step_edit_code(
             api,
             instruction,
             current_code,
             current_tests,
             broadcast,
             run_id
           ),
         {:ok, code} <- Validation.step_validate_and_fix(api, code, broadcast, run_id),
         {:ok, test_code} <-
           Generation.step_edit_tests(api, code, instruction, current_tests, broadcast, run_id),
         {:ok, test_code} <-
           Validation.step_run_and_fix_tests(api, code, test_code, broadcast, run_id),
         {:ok, doc_md} <- Generation.step_generate_docs(api, code, broadcast, run_id) do
      broadcast.({:step_completed, %{step: :submitting}})

      {:ok,
       %{
         code: code,
         test_code: test_code,
         documentation_md: doc_md,
         summary: "Code updated and validated",
         usage: Budget.get_accumulated_usage()
       }}
    end
  end

  # ── Private Planning Steps ──────────────────────────────────────

  @spec step_plan_files(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, [map()]} | {:error, String.t() | atom()}
  defp step_plan_files(api, description, broadcast, run_id) do
    broadcast.({:step_started, %{step: :planning_files}})
    Budget.touch_run(run_id)

    template_type = Budget.template_atom(api.template_type)

    system = """
    #{Prompts.planning_prompt(template_type)}

    #{Templates.get_multi_file_guide()}
    """

    case Budget.guarded_llm_call(description, system) do
      {:ok, content} ->
        case parse_manifest(content) do
          {:ok, files} ->
            Budget.log_step("plan_files", :pass, "Planned #{length(files)} files")
            broadcast.({:step_completed, %{step: :planning_files, manifest: files}})
            {:ok, files}

          {:error, reason} ->
            Budget.log_step("plan_files", :fail, "Invalid manifest: #{reason}")
            fallback = default_manifest()
            broadcast.({:step_completed, %{step: :planning_files, manifest: fallback}})
            {:ok, fallback}
        end

      {:error, reason} ->
        Budget.log_step("plan_files", :fail, inspect(reason))
        fallback = default_manifest()
        broadcast.({:step_completed, %{step: :planning_files, manifest: fallback}})
        {:ok, fallback}
    end
  end

  @spec default_manifest() :: [map()]
  defp default_manifest do
    [
      %{"path" => "/src/handler.ex", "description" => "Main handler", "role" => "handler"},
      %{
        "path" => "/src/request_schema.ex",
        "description" => "Request schema with validation",
        "role" => "helper"
      },
      %{
        "path" => "/src/response_schema.ex",
        "description" => "Response schema",
        "role" => "helper"
      },
      %{"path" => "/src/helpers.ex", "description" => "Helper functions", "role" => "helper"}
    ]
  end

  @spec parse_manifest(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  defp parse_manifest(content) do
    # Extract JSON from response (may be wrapped in ```json blocks)
    json_str =
      case Regex.run(~r/```(?:json)?\s*\n(.*?)```/s, content) do
        [_, json] -> String.trim(json)
        nil -> String.trim(content)
      end

    case Jason.decode(json_str) do
      {:ok, %{"files" => files}} when is_list(files) ->
        handler_count = Enum.count(files, &(&1["role"] == "handler"))

        cond do
          handler_count == 0 ->
            {:error, "No handler file in manifest"}

          handler_count > 1 ->
            {:error, "Multiple handler files in manifest"}

          true ->
            {:ok, ensure_minimum_files(files)}
        end

      {:ok, _} ->
        {:error, "Invalid manifest structure"}

      {:error, reason} ->
        {:error, "JSON parse error: #{inspect(reason)}"}
    end
  end

  # Ensure manifest has at least the 4 required files
  @spec ensure_minimum_files([map()]) :: [map()]
  defp ensure_minimum_files(files) do
    existing_paths = MapSet.new(files, & &1["path"])

    required = [
      %{
        "path" => "/src/request_schema.ex",
        "description" => "Request schema with validation",
        "role" => "helper"
      },
      %{
        "path" => "/src/response_schema.ex",
        "description" => "Response schema",
        "role" => "helper"
      },
      %{"path" => "/src/helpers.ex", "description" => "Helper functions", "role" => "helper"}
    ]

    missing = Enum.reject(required, &MapSet.member?(existing_paths, &1["path"]))
    files ++ missing
  end
end
