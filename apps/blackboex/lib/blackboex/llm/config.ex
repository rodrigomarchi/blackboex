defmodule Blackboex.LLM.Config do
  @moduledoc """
  LLM provider configuration. Reads provider settings and provides
  a unified interface for accessing provider details.
  """

  alias Blackboex.ProjectEnvVars

  defstruct [:name, :model, :api_key_env]

  @type t :: %__MODULE__{
          name: atom(),
          model: String.t(),
          api_key_env: String.t()
        }

  @providers_data [
    [
      name: :anthropic,
      model: "anthropic:claude-sonnet-4-20250514",
      api_key_env: "ANTHROPIC_API_KEY"
    ],
    [name: :openai, model: "openai:gpt-4o", api_key_env: "OPENAI_API_KEY"]
  ]

  @spec default_provider() :: t()
  def default_provider do
    List.first(providers())
  end

  @spec providers() :: [t()]
  def providers do
    Enum.map(@providers_data, &struct!(__MODULE__, &1))
  end

  @spec get_provider(atom()) :: {:ok, t()} | {:error, :unknown_provider}
  def get_provider(name) do
    case Enum.find(providers(), &(&1.name == name)) do
      nil -> {:error, :unknown_provider}
      provider -> {:ok, provider}
    end
  end

  @spec fallback_models() :: [String.t()]
  def fallback_models do
    Enum.map(providers(), & &1.model)
  end

  @spec client() :: module()
  def client do
    Application.get_env(:blackboex, :llm_client, Blackboex.LLM.ReqLLMClient)
  end

  @doc """
  Resolves the LLM client module + per-request options for a given project.

  Returns `{:ok, client_module, [api_key: plaintext]}` when the project has
  an Anthropic key configured, or `{:error, :not_configured}` otherwise.

  Callers merge the returned opts into their `generate_text/stream_text`
  call so the provider receives the project-scoped key. There is no
  platform fallback: projects without a key cannot use AI-assist.

  In test env, when `client/0` resolves to a Mox mock, a dummy key is
  returned so existing tests that configure mock expectations directly
  continue to work without needing to seed a project-level key. Tests
  that specifically cover the `:not_configured` path still trigger it
  by not pre-setting any mock override on this function.
  """
  @spec client_for_project(Ecto.UUID.t()) ::
          {:ok, module(), keyword()} | {:error, :not_configured}
  def client_for_project(project_id) when is_binary(project_id) do
    case ProjectEnvVars.get_llm_key(project_id, :anthropic) do
      {:ok, key} ->
        {:ok, client(), [api_key: key]}

      {:error, :not_configured} ->
        if mock_client?() do
          {:ok, client(), [api_key: "test-mock-key"]}
        else
          {:error, :not_configured}
        end
    end
  end

  @doc """
  Shared three-branch resolver used by every LLM-caller pipeline.

  Precedence (first match wins):

    1. `opts[:client]` — an explicit client module (tests, snippets, CLI).
       Any `:api_key` in opts is forwarded along.
    2. `opts[:project_id]` — resolves the project-scoped Anthropic key via
       `client_for_project/1`. Returns `{:error, :not_configured}` when the
       project has no key (no platform fallback).
    3. Neither is provided — in test env with the Mox client wired the
       bypass returns `{:ok, ClientMock, [api_key: "test-mock-key"]}` so
       `:unit` tests don't need DB access. In dev/prod this branch is
       unreachable and the final clause returns `{:error, :not_configured}`.

  Returns `{:ok, client, llm_opts}` on success or
  `{:error, :not_configured}` when no key can be resolved.
  """
  @spec resolve_client(keyword()) ::
          {:ok, module(), keyword()} | {:error, :not_configured}
  def resolve_client(opts) when is_list(opts) do
    cond do
      opts[:client] != nil ->
        {:ok, opts[:client], Keyword.take(opts, [:api_key])}

      is_binary(opts[:project_id]) ->
        client_for_project(opts[:project_id])

      mock_client?() ->
        # Test-env only: when Mox is wired as the client and callers have
        # neither `:project_id` nor `:client` set (typical `:unit` tests that
        # don't hit the Repo), return the mock with a dummy key so Mox
        # expectations fire without a DB round-trip.
        {:ok, client(), [api_key: "test-mock-key"]}

      true ->
        {:error, :not_configured}
    end
  end

  # The mock bypass is gated purely on the currently-resolved client module
  # (only `Blackboex.LLM.ClientMock`, which is a test-only Mox module,
  # triggers it). In :dev / :prod the resolved client is `ReqLLMClient` and
  # the comparison is always false, so the `:not_configured` branch fires.
  @spec mock_client?() :: boolean()
  defp mock_client? do
    client() == Blackboex.LLM.ClientMock
  end
end
