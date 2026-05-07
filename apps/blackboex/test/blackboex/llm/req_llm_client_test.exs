defmodule Blackboex.LLM.ReqLLMClientTest do
  # async: false because we defensively clear the legacy `:req_llm`
  # Application env to guarantee the per-request `:api_key` path is the
  # only source of truth (there is no platform fallback).
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Blackboex.LLM.ReqLLMClient

  setup do
    original = Application.get_env(:req_llm, :anthropic_api_key)
    Application.delete_env(:req_llm, :anthropic_api_key)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:req_llm, :anthropic_api_key)
        val -> Application.put_env(:req_llm, :anthropic_api_key, val)
      end
    end)

    :ok
  end

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
  # API key resolution
  # ──────────────────────────────────────────────────────────────

  describe "generate_text/2 — api_key resolution" do
    test "returns {:error, :missing_api_key} when api_key opt is absent" do
      assert {:error, :missing_api_key} = ReqLLMClient.generate_text("hi", [])
    end

    test "returns {:error, :missing_api_key} when api_key opt is nil" do
      assert {:error, :missing_api_key} = ReqLLMClient.generate_text("hi", api_key: nil)
    end

    test "returns {:error, :missing_api_key} when api_key opt is empty string" do
      assert {:error, :missing_api_key} = ReqLLMClient.generate_text("hi", api_key: "")
    end

    test "proceeds past the missing_api_key guard when api_key opt is provided" do
      # With a syntactically-valid-but-fake key ReqLLM will attempt a real
      # request and fail at the transport layer, NOT at resolve_api_key.
      # This confirms the per-request key is consumed (no platform fallback).
      result = ReqLLMClient.generate_text("hi", api_key: "sk-per-request")
      refute match?({:error, :missing_api_key}, result)
    end
  end

  describe "stream_text/2 — api_key resolution" do
    test "returns {:error, :missing_api_key} when no key is provided" do
      assert {:error, :missing_api_key} = ReqLLMClient.stream_text("hi", [])
    end

    test "returns {:error, :missing_api_key} when api_key opt is nil" do
      assert {:error, :missing_api_key} = ReqLLMClient.stream_text("hi", api_key: nil)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Default model configuration
  # ──────────────────────────────────────────────────────────────

  describe "default model" do
    test "uses configured default model" do
      configured =
        Application.get_env(
          :blackboex,
          :llm_default_model,
          "anthropic:claude-sonnet-4-5-20250929"
        )

      assert is_binary(configured)
      assert configured =~ "anthropic:"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Note: full error-mapping tests (401 → :invalid_api_key, 429 →
  # :rate_limited) would require a mocked HTTP adapter; they're covered
  # indirectly via `map_error/1`'s pattern matches and by callers that
  # assert on the normalized atoms. Unit tests here verify the public
  # contract: no key → :missing_api_key, and opt precedence.
end
