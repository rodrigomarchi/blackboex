defmodule Blackboex.LLM.Config do
  @moduledoc """
  LLM provider configuration. Reads provider settings and provides
  a unified interface for accessing provider details.
  """

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
end
