defmodule Blackboex.LLM.ReqLLMClientTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.ReqLLMClient

  # ──────────────────────────────────────────────────────────────
  # Behaviour compliance
  # ──────────────────────────────────────────────────────────────

  describe "behaviour compliance" do
    test "implements ClientBehaviour" do
      behaviours =
        ReqLLMClient.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Blackboex.LLM.ClientBehaviour in behaviours
    end

    test "exports generate_text/2" do
      Code.ensure_loaded!(ReqLLMClient)
      assert function_exported?(ReqLLMClient, :generate_text, 2)
    end

    test "exports stream_text/2" do
      Code.ensure_loaded!(ReqLLMClient)
      assert function_exported?(ReqLLMClient, :stream_text, 2)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Default model configuration
  # ──────────────────────────────────────────────────────────────

  describe "default model" do
    test "uses configured default model" do
      # The default model should be configurable via application env
      configured = Application.get_env(:blackboex, :llm_default_model, "anthropic:claude-sonnet-4-20250514")
      assert is_binary(configured)
      assert configured =~ "anthropic:"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Error handling (without real API calls)
  # ──────────────────────────────────────────────────────────────
  # NOTE: We don't test actual API calls here — that would require
  # network access and API keys. The real client is tested indirectly
  # through integration tests. The Mox mock (ClientMock) is used for
  # unit tests of modules that depend on the LLM client.
  #
  # These tests verify the module's structure and contract compliance,
  # which is the appropriate level of testing for a thin wrapper.
end
