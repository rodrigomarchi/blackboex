defmodule Blackboex.CodeGen.UnifiedPipelineTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  import Mox

  alias Blackboex.CodeGen.UnifiedPipeline

  setup :verify_on_exit!

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
        UnifiedPipeline.validate_on_save(@valid_handler_code, "some test code", :computation)

      assert result_test_code == "some test code"
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
  end

  # ── generate_edit_only: LLM failure ───────────────────────────

  describe "generate_edit_only/5" do
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

  # ── run_for_edit: LLM failure ──────────────────────���──────────

  describe "run_for_edit/5" do
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
  end
end
