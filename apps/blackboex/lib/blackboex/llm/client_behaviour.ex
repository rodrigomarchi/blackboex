defmodule Blackboex.LLM.ClientBehaviour do
  @moduledoc """
  Behaviour defining the interface for LLM clients.
  Allows swapping real implementations with mocks in tests.

  ## Per-request authentication

  Callers MUST supply the provider API key via the `:api_key` option:

      client.generate_text(prompt, api_key: "sk-ant-...", system: "...")

  There is **no platform fallback** — when `:api_key` is missing the call
  returns `{:error, :missing_api_key}`. Callers resolve the project-scoped
  key through `Blackboex.LLM.Config.client_for_project/1` and thread the
  returned opts into the call.

  ## Error mapping

  The real client maps common HTTP statuses to stable atoms so the UI can
  surface actionable messages:

    * `401` → `{:error, :invalid_api_key}`
    * `429` → `{:error, :rate_limited}`

  Mocks may return arbitrary `{:error, reason}` tuples.
  """

  @callback generate_text(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{content: String.t(), usage: map()}} | {:error, term()}

  @callback stream_text(prompt :: String.t(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
end
