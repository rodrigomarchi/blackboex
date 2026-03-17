defmodule Blackboex.LLM.ClientBehaviour do
  @moduledoc """
  Behaviour defining the interface for LLM clients.
  Allows swapping real implementations with mocks in tests.
  """

  @callback generate_text(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{content: String.t(), usage: map()}} | {:error, term()}

  @callback stream_text(prompt :: String.t(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
end
