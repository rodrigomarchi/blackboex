defmodule Blackboex.LLM do
  @moduledoc """
  The LLM context. Manages LLM client operations, usage tracking,
  circuit breaking, and rate limiting.
  """

  alias Blackboex.LLM.Usage
  alias Blackboex.Repo

  # ── Usage ───────────────────────────────────────────────────

  @spec record_usage(map()) :: {:ok, Usage.t()} | {:error, Ecto.Changeset.t()}
  def record_usage(attrs) do
    %Usage{}
    |> Usage.changeset(attrs)
    |> Repo.insert()
  end

  # ── Circuit Breaker ─────────────────────────────────────────

  defdelegate allow?(provider), to: Blackboex.LLM.CircuitBreaker
  defdelegate record_success(provider), to: Blackboex.LLM.CircuitBreaker
  defdelegate record_failure(provider), to: Blackboex.LLM.CircuitBreaker

  # ── Security Config ─────────────────────────────────────────

  defdelegate allowed_modules(), to: Blackboex.LLM.SecurityConfig
  defdelegate prohibited_modules(), to: Blackboex.LLM.SecurityConfig
end
