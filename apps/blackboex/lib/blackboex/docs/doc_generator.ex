defmodule Blackboex.Docs.DocGenerator do
  @moduledoc """
  Generates Markdown documentation for an API using the LLM.
  """

  require Logger

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.DocPrompts
  alias Blackboex.Docs.OpenApiGenerator
  alias Blackboex.LLM.Config

  @spec generate(Api.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(%Api{} = api, opts \\ []) do
    openapi_spec = OpenApiGenerator.generate(api, opts)
    prompt = DocPrompts.build_doc_prompt(api, openapi_spec)
    system = DocPrompts.system_prompt()
    client = Keyword.get_lazy(opts, :client, &Config.client/0)

    case client.generate_text(prompt, system: system) do
      {:ok, %{content: content}} ->
        {:ok, String.trim(content)}

      {:error, reason} ->
        Logger.warning("Doc generation failed: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end
end
