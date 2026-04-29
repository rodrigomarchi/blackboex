defmodule Blackboex.MockDefaults do
  @moduledoc """
  Default Mox stubs for common mocked services.

  These named setup functions provide sensible defaults so tests that
  don't care about mock behavior don't need to configure stubs manually.
  Individual tests can override with `expect/3`.
  """

  import Mox

  @doc """
  Named setup: stubs LLM client with safe defaults.

  Usage: `setup :stub_llm_client`
  """
  @spec stub_llm_client(map()) :: :ok
  def stub_llm_client(_context \\ %{}) do
    stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
      {:ok, Stream.map(["ok"], &{:token, &1})}
    end)

    stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
      {:ok, "mocked response"}
    end)

    :ok
  end
end
