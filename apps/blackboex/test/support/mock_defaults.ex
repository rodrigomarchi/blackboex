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

  @doc """
  Named setup: stubs Stripe client with safe defaults.

  Usage: `setup :stub_stripe`
  """
  @spec stub_stripe(map()) :: :ok
  def stub_stripe(_context \\ %{}) do
    stub(Blackboex.Billing.StripeClientMock, :create_checkout_session, fn _params ->
      {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/test"}}
    end)

    stub(Blackboex.Billing.StripeClientMock, :create_portal_session, fn _cid, _return_url ->
      {:ok, %{url: "https://billing.stripe.com/test"}}
    end)

    :ok
  end
end
