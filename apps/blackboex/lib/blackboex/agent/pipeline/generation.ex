defmodule Blackboex.Agent.Pipeline.Generation do
  @moduledoc """
  Code generation step functions for the code pipeline.
  """

  require Logger

  alias Blackboex.Agent.FixPrompts
  alias Blackboex.Agent.Pipeline.Budget
  alias Blackboex.Agent.Pipeline.CodeParser
  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.DiffEngine
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM.EditPrompts
  alias Blackboex.LLM.Prompts
  alias Blackboex.LLM.Templates
  alias Blackboex.Testing.TestGenerator

  @type broadcast_fn :: (term() -> :ok)
  @type file_entry :: %{path: String.t(), content: String.t(), file_type: String.t()}

  # ── Step 1: Generate Code ──────────────────────────────────────

  @spec step_generate_code(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_generate_code(api, description, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    Budget.touch_run(run_id)

    template_type = Budget.template_atom(api.template_type)

    system = """
    #{Prompts.system_prompt()}

    #{Templates.get(template_type)}

    Generate the handler code for this API.
    Return the code in a single ```elixir code block. No explanations outside the block.
    """

    case Budget.guarded_llm_call(description, system) do
      {:ok, content} ->
        code = CodeParser.extract_code(content)

        Budget.log_step(
          "generate",
          :pass,
          "Generated #{String.length(code)} chars of handler code"
        )

        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        Budget.log_step("generate", :fail, reason)
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
  def step_edit_code(_api, instruction, current_code, _current_tests, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    Budget.touch_run(run_id)

    system = EditPrompts.system_prompt()
    prompt = EditPrompts.build_edit_prompt(current_code, instruction, [])

    case Budget.guarded_llm_call(prompt, system) do
      {:ok, content} ->
        code = CodeParser.apply_edits_or_extract(current_code, content)
        Budget.log_step("edit_code", :pass, "Applied edit: #{String.slice(instruction, 0, 100)}")
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        Budget.log_step("edit_code", :fail, reason)
        broadcast.({:step_failed, %{step: :generating_code, error: reason}})
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
  def step_edit_tests(api, code, instruction, current_tests, broadcast, run_id) do
    if String.trim(current_tests) == "" do
      step_generate_tests(api, code, broadcast, run_id)
    else
      broadcast.({:step_started, %{step: :generating_tests}})
      Budget.touch_run(run_id)

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

      case Budget.guarded_llm_call(prompt, system) do
        {:ok, content} ->
          apply_test_edits_or_skip(content, current_tests, broadcast)

        {:error, reason} ->
          Budget.log_step("edit_tests", :fail, reason)
          # Fallback to full test generation
          step_generate_tests(api, code, broadcast, run_id)
      end
    end
  end

  @spec apply_test_edits_or_skip(String.t(), String.t(), broadcast_fn()) ::
          {:ok, String.t()}
  defp apply_test_edits_or_skip(content, current_tests, broadcast) do
    if String.contains?(content, "NO CHANGES NEEDED") do
      Budget.log_step("edit_tests", :pass, "No test changes needed")
      broadcast.({:step_completed, %{step: :generating_tests, test_code: current_tests}})
      {:ok, current_tests}
    else
      test_code = CodeParser.apply_edits_or_extract(current_tests, content)
      Budget.log_step("edit_tests", :pass, "Tests updated via diff")
      broadcast.({:step_completed, %{step: :generating_tests, test_code: test_code}})
      {:ok, test_code}
    end
  end

  # ── Step 5: Generate Tests ─────────────────────────────────────

  @spec step_generate_tests(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_generate_tests(api, code, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_tests}})
    Budget.touch_run(run_id)

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

  # ── Step 7: Generate Documentation ────────────────────────────

  @spec step_generate_docs(Api.t(), String.t(), broadcast_fn(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def step_generate_docs(api, code, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_docs}})
    Budget.touch_run(run_id)

    doc_tc = Process.get(:token_callback)
    doc_opts = [source_code: code] ++ if(doc_tc, do: [token_callback: doc_tc], else: [])

    case DocGenerator.generate(api, doc_opts) do
      {:ok, %{doc: doc} = result} ->
        Budget.accumulate_usage(result[:usage])
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

  # ── Multi-File Steps ─────────────────────────────────────────

  @spec step_generate_handler(
          Api.t(),
          String.t(),
          [map()],
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, String.t()} | {:error, String.t() | atom()}
  def step_generate_handler(api, description, manifest, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    broadcast.({:file_started, %{path: "/src/handler.ex"}})
    Budget.touch_run(run_id)

    template_type = Budget.template_atom(api.template_type)

    system = """
    #{Prompts.system_prompt()}

    #{Templates.get(template_type)}

    #{Prompts.handler_generation_prompt(description, manifest)}
    """

    case Budget.guarded_llm_call("Generate the handler code as specified above.", system) do
      {:ok, content} ->
        code = CodeParser.extract_code(content)

        Budget.log_step(
          "generate_handler",
          :pass,
          "Generated handler: #{String.length(code)} chars"
        )

        broadcast.({:file_completed, %{path: "/src/handler.ex"}})
        broadcast.({:step_completed, %{step: :generating_code, code: code}})
        {:ok, code}

      {:error, reason} ->
        Budget.log_step("generate_handler", :fail, inspect(reason))
        broadcast.({:step_failed, %{step: :generating_code, error: inspect(reason)}})
        {:error, reason}
    end
  end

  @spec step_generate_helpers(
          Api.t(),
          String.t(),
          String.t(),
          [map()],
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  def step_generate_helpers(_api, _description, _handler_code, manifest, broadcast, _run_id)
      when length(manifest) <= 1 do
    broadcast.({:step_completed, %{step: :generating_helpers}})
    {:ok, []}
  end

  def step_generate_helpers(_api, description, handler_code, manifest, broadcast, run_id) do
    helper_manifests = Enum.filter(manifest, &(&1["role"] == "helper"))
    generated_so_far = [%{"path" => "/src/handler.ex", "content" => handler_code}]

    generate_helpers_sequentially(
      helper_manifests,
      generated_so_far,
      description,
      handler_code,
      broadcast,
      run_id,
      []
    )
  end

  @spec generate_helpers_sequentially(
          [map()],
          [map()],
          String.t(),
          String.t(),
          broadcast_fn(),
          String.t() | nil,
          [file_entry()]
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  defp generate_helpers_sequentially([], _ctx, _desc, _handler, broadcast, _run_id, acc) do
    broadcast.({:step_completed, %{step: :generating_helpers}})
    {:ok, Enum.reverse(acc)}
  end

  defp generate_helpers_sequentially(
         [file_manifest | rest],
         generated_so_far,
         description,
         handler_code,
         broadcast,
         run_id,
         acc
       ) do
    path = file_manifest["path"]
    file_desc = file_manifest["description"]

    broadcast.({:step_started, %{step: :generating_helpers}})
    broadcast.({:file_started, %{path: path}})
    Budget.touch_run(run_id)

    context =
      generated_so_far
      |> Enum.map(fn f -> "### #{f["path"]}\n```elixir\n#{f["content"]}\n```" end)
      |> Enum.join("\n\n")

    system = """
    #{Prompts.system_prompt()}

    You are generating a single helper file for an Elixir API project.

    ## API Description
    #{description}

    ## Already Generated Files (reference only)
    #{context}

    ## File to Generate: #{path}
    Description: #{file_desc}

    Generate ONLY the code for this file. Return it in a single ```elixir block.
    Follow the same rules as the handler: @moduledoc, @doc, @spec on public functions.
    """

    case Budget.guarded_llm_call("Generate #{path} as described.", system) do
      {:ok, content} ->
        code = CodeParser.extract_code(content)
        entry = %{path: path, content: code, file_type: "source"}

        Budget.log_step(
          "generate_helper",
          :pass,
          "Generated #{path}: #{String.length(code)} chars"
        )

        broadcast.({:file_completed, %{path: path}})

        new_context = generated_so_far ++ [%{"path" => path, "content" => code}]

        generate_helpers_sequentially(
          rest,
          new_context,
          description,
          handler_code,
          broadcast,
          run_id,
          [entry | acc]
        )

      {:error, reason} ->
        Budget.log_step("generate_helper", :fail, "#{path}: #{inspect(reason)}")
        broadcast.({:step_failed, %{step: :generating_helpers, error: inspect(reason)}})
        {:error, reason}
    end
  end

  @spec build_source_files(String.t(), [file_entry()]) :: [file_entry()]
  def build_source_files(handler_code, helper_files) do
    handler = %{path: "/src/handler.ex", content: handler_code, file_type: "source"}
    [handler | helper_files]
  end

  @spec get_handler_content([file_entry()]) :: String.t()
  def get_handler_content(source_files) do
    case Enum.find(source_files, &(&1.path == "/src/handler.ex")) do
      %{content: content} -> content
      nil -> ""
    end
  end

  @spec step_generate_test_files(
          Api.t(),
          [file_entry()],
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  def step_generate_test_files(api, source_files, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_tests}})
    Budget.touch_run(run_id)

    # Generate tests using existing TestGenerator with concatenated source
    handler_code = get_handler_content(source_files)
    tc = Process.get(:token_callback)
    gen_opts = if tc, do: [token_callback: tc], else: []

    case TestGenerator.generate_tests_for_code(
           handler_code,
           api.template_type || "computation",
           gen_opts
         ) do
      {:ok, %{code: test_code}} ->
        test_files = [
          %{path: "/test/handler_test.ex", content: test_code, file_type: "test"}
        ]

        broadcast.({:step_completed, %{step: :generating_tests, test_code: test_code}})
        {:ok, test_files}

      {:error, reason} ->
        broadcast.({:step_failed, %{step: :generating_tests, error: inspect(reason)}})
        {:error, "Test generation failed: #{inspect(reason)}"}
    end
  end

  @spec step_edit_files(
          Api.t(),
          String.t(),
          [file_entry()],
          broadcast_fn(),
          String.t() | nil
        ) :: {:ok, [file_entry()]} | {:error, String.t() | atom()}
  def step_edit_files(_api, instruction, current_files, broadcast, run_id) do
    broadcast.({:step_started, %{step: :generating_code}})
    Budget.touch_run(run_id)

    system = EditPrompts.system_prompt()

    prompt = Prompts.multi_file_edit_prompt(current_files, instruction)

    case Budget.guarded_llm_call(prompt, system) do
      {:ok, content} ->
        edited_files = apply_path_annotated_edits(current_files, content)
        Budget.log_step("edit_files", :pass, "Applied edit: #{String.slice(instruction, 0, 100)}")
        broadcast.({:step_completed, %{step: :generating_code}})
        {:ok, edited_files}

      {:error, reason} ->
        Budget.log_step("edit_files", :fail, inspect(reason))
        broadcast.({:step_failed, %{step: :generating_code, error: inspect(reason)}})
        {:error, reason}
    end
  end

  @spec apply_path_annotated_edits([file_entry()], String.t()) :: [file_entry()]
  def apply_path_annotated_edits(files, response) do
    # Parse path-annotated SEARCH/REPLACE blocks:
    # <<<< /src/filename.ex
    # <<<<<<< SEARCH
    # ...
    # =======
    # ...
    # >>>>>>> REPLACE
    file_blocks = parse_path_annotated_blocks(response)

    Enum.map(files, &apply_blocks_to_file(&1, file_blocks))
  end

  @spec apply_blocks_to_file(file_entry(), map()) :: file_entry()
  defp apply_blocks_to_file(file, file_blocks) do
    case Map.get(file_blocks, file.path) do
      nil ->
        file

      blocks ->
        apply_search_replace_to_file(file, blocks)
    end
  end

  @spec apply_search_replace_to_file(file_entry(), [map()]) :: file_entry()
  defp apply_search_replace_to_file(file, blocks) do
    case DiffEngine.apply_search_replace(file.content, blocks) do
      {:ok, patched} ->
        if CodeParser.code_looks_corrupted?(file.content, patched) do
          Logger.warning("Patched #{file.path} looks corrupted, keeping original")
          file
        else
          %{file | content: patched}
        end

      {:error, :search_not_found, _} ->
        Logger.warning("Search/replace failed for #{file.path}, keeping original")
        file
    end
  end

  @spec parse_path_annotated_blocks(String.t()) :: %{String.t() => [map()]}
  defp parse_path_annotated_blocks(response) do
    # Split by <<<< /path markers
    ~r/<<<<\s+(\/\S+\.ex)\s*\n/
    |> Regex.split(response, include_captures: true)
    |> parse_path_parts(%{})
  end

  @spec parse_path_parts([String.t()], map()) :: map()
  defp parse_path_parts([], acc), do: acc
  defp parse_path_parts([_non_match], acc), do: acc

  defp parse_path_parts([_pre, path_line, block_content | rest], acc) do
    # path_line is the full match "<<<< /src/handler.ex\n" — extract just the path
    path = extract_path_from_marker(path_line)
    blocks = FixPrompts.parse_search_replace_blocks(block_content)
    existing = Map.get(acc, path, [])
    parse_path_parts(rest, Map.put(acc, path, existing ++ blocks))
  end

  defp parse_path_parts([_ | rest], acc), do: parse_path_parts(rest, acc)

  @spec extract_path_from_marker(String.t()) :: String.t()
  defp extract_path_from_marker(marker_line) do
    case Regex.run(~r/(\/\S+\.ex)/, marker_line) do
      [_, path] -> path
      nil -> String.trim(marker_line)
    end
  end
end
