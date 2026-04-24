defmodule Blackboex.LLM.ConfigTest do
  # Async false because `client_for_project/1` touches the DB via
  # `ProjectEnvVars.get_llm_key/2`.
  use Blackboex.DataCase, async: false

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

  describe "client/0" do
    test "returns the configured mock in the test environment" do
      assert Config.client() == Blackboex.LLM.ClientMock
    end
  end

  describe "client_for_project/1" do
    setup do
      user = Blackboex.AccountsFixtures.user_fixture()
      org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
      %{user: user, org: org}
    end

    test "returns :not_configured when the project has no Anthropic key",
         %{user: user, org: org} do
      # Swap to non-mock client so the production :not_configured path is
      # exercised instead of the test-only mock bypass.
      original_client = Application.get_env(:blackboex, :llm_client)
      Application.put_env(:blackboex, :llm_client, Blackboex.LLM.ReqLLMClient)
      on_exit(fn -> Application.put_env(:blackboex, :llm_client, original_client) end)

      project = Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org})
      assert {:error, :not_configured} = Config.client_for_project(project.id)
    end

    test "returns {:ok, client, [api_key: plaintext]} once a key is configured",
         %{user: user, org: org} do
      project = Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org})

      {:ok, _env_var} =
        Blackboex.ProjectEnvVars.put_llm_key(project.id, :anthropic, "sk-ant-test-xyz", org.id)

      assert {:ok, client, opts} = Config.client_for_project(project.id)
      assert client == Blackboex.LLM.ClientMock
      assert Keyword.fetch!(opts, :api_key) == "sk-ant-test-xyz"
    end

    test "each project gets its own key", %{user: user, org: org} do
      project_a =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "A"})

      project_b =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "B"})

      {:ok, _} = Blackboex.ProjectEnvVars.put_llm_key(project_a.id, :anthropic, "key-a", org.id)
      {:ok, _} = Blackboex.ProjectEnvVars.put_llm_key(project_b.id, :anthropic, "key-b", org.id)

      assert {:ok, _, opts_a} = Config.client_for_project(project_a.id)
      assert {:ok, _, opts_b} = Config.client_for_project(project_b.id)
      assert Keyword.fetch!(opts_a, :api_key) == "key-a"
      assert Keyword.fetch!(opts_b, :api_key) == "key-b"
    end
  end
end
