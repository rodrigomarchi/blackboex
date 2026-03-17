defmodule Blackboex.LLM.ConfigTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.Config

  describe "default_provider/0" do
    test "returns configured default provider" do
      provider = Config.default_provider()
      assert provider.name == :anthropic
      assert is_binary(provider.model)
    end
  end

  describe "providers/0" do
    test "lists available providers" do
      providers = Config.providers()
      assert length(providers) >= 2
      names = Enum.map(providers, & &1.name)
      assert :anthropic in names
      assert :openai in names
    end

    test "each provider has required fields" do
      for provider <- Config.providers() do
        assert is_atom(provider.name)
        assert is_binary(provider.model)
        assert is_binary(provider.api_key_env)
      end
    end
  end

  describe "get_provider/1" do
    test "returns config for known provider" do
      {:ok, provider} = Config.get_provider(:anthropic)
      assert provider.name == :anthropic
      assert provider.model =~ "anthropic:"
      assert provider.api_key_env == "ANTHROPIC_API_KEY"
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = Config.get_provider(:nonexistent)
    end
  end
end
