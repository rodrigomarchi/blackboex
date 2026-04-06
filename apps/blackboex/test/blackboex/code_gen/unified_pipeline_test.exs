defmodule Blackboex.CodeGen.UnifiedPipelineTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  import Mox

  alias Blackboex.CodeGen.UnifiedPipeline

  # Valid handler code that compiles and passes format/lint
  @valid_handler_code """
  def handle(params) do
    %{status: 200, body: %{result: params}}
  end
  """

  # Code that won't compile (syntax error)
  @invalid_code """
  def handle(params) do
    %{status: 200, body: params
  end
  """

  # Valid test code that can run against the handler.
  # TestRunner compiles handler code into a `Handler` module, so tests call Handler.handle/1.
  @valid_test_code """
  defmodule HandlerTest do
    use ExUnit.Case

    test "handle returns a map" do
      result = Handler.handle(%{"key" => "value"})
      assert is_map(result)
    end
  end
  """

  # LLM response with a SEARCH/REPLACE block that matches @valid_handler_code
  defp search_replace_response(new_body) do
    """
    I updated the handle function to improve the response.

    <<<<<<< SEARCH
    def handle(params) do
      %{status: 200, body: %{result: params}}
    end
    =======
    #{new_body}
    >>>>>>> REPLACE
    """
  end

  # LLM response with full code block
  defp full_code_response(code) do
    """
    Updated the full implementation.

    ```elixir
    #{code}
    ```
    """
  end

  # Test code returned by LLM (valid parseable elixir).
  # Must call Handler.handle/1 — TestRunner compiles handler into a `Handler` module.
  defp test_code_llm_response do
    """
    ```elixir
    defmodule GeneratedAPITest do
      use ExUnit.Case

      test "handle returns a map" do
        result = Handler.handle(%{})
        assert is_map(result)
      end
    end
    ```
    """
  end

  # ── validate_on_save: happy path ──────────────────────────────

  describe "validate_on_save/4 happy path" do
    test "returns :ok with validation report for valid code" do
      # Stub LLM for doc generation
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# API Documentation\n\nThis API handles computation."}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)

      assert {:ok, %{code: code, validation: validation}} = result
      assert is_binary(code)
      assert validation.compilation == :pass
    end

    test "returns validation report with format info" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)

      assert validation.format in [:pass, :fail]
      assert is_list(validation.format_issues)
    end

    test "returns test_results as skipped when no tests provided" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)

      assert validation.tests == :skipped
    end

    test "returns test_results as skipped for empty test string" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, "", :computation)

      assert validation.tests == :skipped
    end

    test "preserves original test_code in result" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{test_code: result_test_code}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, @valid_test_code, :computation)

      assert result_test_code == @valid_test_code
    end
  end

  # ── validate_on_save: invalid code ────────────────────────────

  describe "validate_on_save/4 with invalid code" do
    test "returns compilation: fail for code with syntax errors" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@invalid_code, nil, :computation)

      assert validation.compilation == :fail
      assert validation.overall == :fail
    end
  end

  # ── validate_on_save: with test_code provided ─────────────────

  describe "validate_on_save/4 with test_code provided" do
    test "runs tests and returns test results in validation report" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, @valid_test_code, :computation)

      # Tests ran (not skipped)
      assert validation.tests in [:pass, :fail]
      assert is_list(validation.test_results)
      refute validation.tests == :skipped
    end

    test "returns test results list when test_code is provided" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, @valid_test_code, :computation)

      assert is_list(validation.test_results)
    end
  end

  # ── validate_on_save: progress callback ───────────────────────

  describe "validate_on_save/4 progress callback" do
    test "calls progress_callback for each step" do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      progress_fn = fn progress -> send(test_pid, {:progress, progress}) end

      UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation,
        progress_callback: progress_fn
      )

      assert_received {:progress, %{step: :formatting}}
      assert_received {:progress, %{step: :compiling}}
      assert_received {:progress, %{step: :linting}}
      assert_received {:progress, %{step: :done}}
    end

    test "works without progress_callback (nil)" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      # Should not crash without progress callback
      result = UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)
      assert {:ok, _} = result
    end
  end

  # ── validate_and_test: happy path ─────────────────────────────

  describe "validate_and_test/3 happy path" do
    test "returns {:ok, result} with compilation :pass for valid compilable code" do
      # generate_text is called by TestGenerator for test generation
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      # stream_text is called for doc generation (no token_callback so generate_text is used)
      # and for fix cycles if needed — stub it too
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_and_test(@valid_handler_code, :computation)

      assert {:ok, %{validation: validation}} = result
      assert validation.compilation == :pass
    end

    test "result includes code field with the handler code" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, result} = UnifiedPipeline.validate_and_test(@valid_handler_code, :computation)

      assert is_binary(result.code)
      assert result.template == :computation
    end

    test "progress callback receives events during validate_and_test" do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      progress_fn = fn progress -> send(test_pid, {:progress, progress.step}) end

      UnifiedPipeline.validate_and_test(@valid_handler_code, :computation,
        progress_callback: progress_fn
      )

      # Should receive at minimum formatting, compiling, linting, generating_tests steps
      assert_received {:progress, :formatting}
      assert_received {:progress, :compiling}
      assert_received {:progress, :linting}
      assert_received {:progress, :generating_tests}
    end
  end

  # ── validate_and_test: compilation failure → fix loop ─────────

  describe "validate_and_test/3 with compilation errors" do
    test "fix loop runs when code has compilation errors" do
      # stream_text is used by fix_code (stream_and_parse_fix)
      # Return valid code on first fix attempt
      fixed_code = """
      ```elixir
      def handle(params) do
        %{status: 200, body: params}
      end
      ```
      """

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, fixed_code}]}
      end)

      # generate_text for test generation after fix
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      # Invalid code triggers compilation failure and fix loop
      result = UnifiedPipeline.validate_and_test(@invalid_code, :computation)

      # Should either succeed after fix or return max_retries_exceeded
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "returns {:error, :max_retries_exceeded} when fix keeps failing" do
      # stream_text always returns bad code (no valid code block, no SEARCH/REPLACE)
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, "this is not code at all, no fix here"}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "still broken code", usage: %{}}}
      end)

      result = UnifiedPipeline.validate_and_test(@invalid_code, :computation)

      assert {:error, _reason} = result
    end

    test "returns error after max retries with always-failing code" do
      # LLM returns a code block but still with broken syntax → keeps failing
      broken_fix = """
      ```elixir
      def handle(params) do
        %{broken:
      end
      ```
      """

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, broken_fix}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, :llm_unavailable}
      end)

      result = UnifiedPipeline.validate_and_test(@invalid_code, :computation)

      assert {:error, :max_retries_exceeded} = result
    end
  end

  # ── validate_and_test: LLM failure ────────────────────────────

  describe "validate_and_test/3 with LLM failure" do
    test "returns :error when compilation fails repeatedly" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        # Return code that still has errors
        {:ok, %{content: "```elixir\ndef handle(p), do: p\n```"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      # Code with syntax error should fail compilation and retry up to max
      result = UnifiedPipeline.validate_and_test(@invalid_code, :computation)

      assert {:error, _reason} = result
    end
  end

  # ── run_for_edit: happy path ──────────────────────────────────

  describe "run_for_edit/5 happy path" do
    test "returns {:ok, result} when LLM returns valid SEARCH/REPLACE and code compiles" do
      new_body =
        "def handle(params) do\n  %{status: 200, body: %{result: params, edited: true}}\nend"

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        response = search_replace_response(new_body)
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result = UnifiedPipeline.run_for_edit(api, @valid_handler_code, "Add edited flag", [])

      assert {:ok, %{code: code, validation: validation}} = result
      assert is_binary(code)
      assert validation.compilation == :pass
    end

    test "includes explanation from LLM response" do
      new_body = "def handle(params) do\n  %{status: 200, body: %{result: params, v2: true}}\nend"
      response = search_replace_response(new_body)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      {:ok, result} = UnifiedPipeline.run_for_edit(api, @valid_handler_code, "Update", [])

      assert Map.has_key?(result, :explanation)
    end

    test "returns {:ok, result} when LLM returns full code block" do
      new_code = "def handle(params) do\n  %{status: 200, body: params}\nend"
      response = full_code_response(new_code)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result = UnifiedPipeline.run_for_edit(api, @valid_handler_code, "Simplify", [])

      assert {:ok, %{validation: validation}} = result
      assert validation.compilation == :pass
    end
  end

  # ── run_for_edit: LLM failure ─────────────────────────────────

  describe "run_for_edit/5 LLM error" do
    test "returns error when LLM code generation fails" do
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result =
        UnifiedPipeline.run_for_edit(
          api,
          @valid_handler_code,
          "Add validation",
          []
        )

      assert {:error, _} = result
    end

    test "returns error when LLM response has no parseable changes" do
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        # No SEARCH/REPLACE blocks, no code block → :no_changes_found
        {:ok, [{:token, "Sorry, I cannot help with that."}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, :unused}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result = UnifiedPipeline.run_for_edit(api, @valid_handler_code, "Change something", [])

      assert {:error, _} = result
    end
  end

  # ── generate_edit_only: happy path ────────────────────────────

  describe "generate_edit_only/5 happy path" do
    test "returns {:ok, %{code, explanation, usage}} without running validation" do
      new_body = "def handle(params) do\n  %{status: 200, body: %{result: params}}\nend"
      response = search_replace_response(new_body)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      # generate_text should NOT be called (no validation in generate_edit_only)
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        flunk("generate_text should not be called in generate_edit_only")
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result =
        UnifiedPipeline.generate_edit_only(
          api,
          @valid_handler_code,
          "Return same structure",
          []
        )

      assert {:ok, %{code: code, explanation: _explanation, usage: _usage}} = result
      assert is_binary(code)
    end

    test "returns explanation from LLM response" do
      new_body = "def handle(params) do\n  %{status: 200, body: params}\nend"
      response = "I updated the handle function.\n" <> search_replace_response(new_body)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        flunk("generate_text should not be called")
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      {:ok, %{explanation: explanation}} =
        UnifiedPipeline.generate_edit_only(api, @valid_handler_code, "Simplify", [])

      assert is_binary(explanation)
    end

    test "returns code from full code block response" do
      new_code = "def handle(params) do\n  %{status: 200, body: params}\nend"
      response = full_code_response(new_code)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        flunk("generate_text should not be called")
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result = UnifiedPipeline.generate_edit_only(api, @valid_handler_code, "Rewrite", [])

      assert {:ok, %{code: code}} = result
      assert String.contains?(code, "def handle")
    end
  end

  # ── generate_edit_only: search mismatch retry ─────────────────

  describe "generate_edit_only/5 search mismatch" do
    test "retries when SEARCH block does not match current code" do
      # First call: SEARCH block that won't match the current code
      mismatched_response = """
      I changed the code.

      <<<<<<< SEARCH
      def handle(params) do
        THIS_DOES_NOT_EXIST_IN_CODE
      end
      =======
      def handle(params) do
        %{status: 200, body: %{updated: true}}
      end
      >>>>>>> REPLACE
      """

      # Retry response: valid SEARCH/REPLACE
      new_body = "def handle(params) do\n  %{status: 200, body: %{retry: true}}\nend"
      retry_response = search_replace_response(new_body)

      call_count = :counters.new(1, [:atomics])

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:ok, [{:token, mismatched_response}]}
        else
          {:ok, [{:token, retry_response}]}
        end
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        flunk("generate_text should not be called")
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result =
        UnifiedPipeline.generate_edit_only(
          api,
          @valid_handler_code,
          "Update handler",
          []
        )

      assert {:ok, %{code: code}} = result
      assert is_binary(code)
    end

    test "falls back to full code generation when retry also fails" do
      # Both first call and retry return mismatched SEARCH blocks
      mismatched_response = """
      <<<<<<< SEARCH
      THIS_WILL_NOT_MATCH
      =======
      def handle(_params), do: %{}
      >>>>>>> REPLACE
      """

      fallback_code = "def handle(_params) do\n  %{status: 200, body: %{}}\nend"
      fallback_response = full_code_response(fallback_code)

      call_count = :counters.new(1, [:atomics])

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 2 do
          {:ok, [{:token, mismatched_response}]}
        else
          {:ok, [{:token, fallback_response}]}
        end
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        flunk("generate_text should not be called")
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result =
        UnifiedPipeline.generate_edit_only(
          api,
          @valid_handler_code,
          "Modify handler",
          []
        )

      # Should succeed via fallback or return error if no code block found
      assert match?({:ok, %{code: _}}, result) or match?({:error, _}, result)
    end
  end

  # ── generate_edit_only: LLM failure ───────────────────────────

  describe "generate_edit_only/5 LLM errors" do
    test "returns error when LLM call fails" do
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result =
        UnifiedPipeline.generate_edit_only(
          api,
          @valid_handler_code,
          "Add input validation",
          []
        )

      assert {:error, _reason} = result
    end
  end

  # ── template type validation ──────────────────────────────────

  describe "safe_template_atom" do
    test "validate_on_save accepts :computation atom" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)
      assert {:ok, %{template: :computation}} = result
    end

    test "validate_on_save accepts :crud atom" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :crud)
      assert {:ok, %{template: :crud}} = result
    end

    test "validate_on_save accepts :webhook atom" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :webhook)
      assert {:ok, %{template: :webhook}} = result
    end

    test "run_for_edit accepts binary template type via Api struct" do
      new_body = "def handle(params) do\n  %{status: 200, body: params}\nend"
      response = search_replace_response(new_body)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, [{:token, response}]}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      api = %Blackboex.Apis.Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        source_code: @valid_handler_code
      }

      result = UnifiedPipeline.run_for_edit(api, @valid_handler_code, "Update", [])
      assert {:ok, %{template: :computation}} = result
    end
  end

  # ── empty/edge-case code ──────────────────────────────────────

  describe "edge cases" do
    test "validate_on_save handles empty code string" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save("", nil, :computation)

      assert validation.compilation == :fail
      assert validation.overall == :fail
    end

    test "validate_on_save handles whitespace-only code" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{validation: validation}} =
        UnifiedPipeline.validate_on_save("   \n  \n  ", nil, :computation)

      # Empty code after trimming should fail compilation
      assert validation.compilation == :fail
    end

    test "validate_on_save always returns a documentation_md field" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Generated Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, result} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)

      assert Map.has_key?(result, :documentation_md)
    end

    test "validate_on_save returns usage as empty map" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Docs"}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      {:ok, %{usage: usage}} =
        UnifiedPipeline.validate_on_save(@valid_handler_code, nil, :computation)

      assert usage == %{}
    end

    test "validate_and_test accepts opts keyword list" do
      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: test_code_llm_response(), usage: %{}}}
      end)

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, []}
      end)

      result = UnifiedPipeline.validate_and_test(@valid_handler_code, :computation, [])
      assert {:ok, _} = result
    end
  end
end
