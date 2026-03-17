defmodule Blackboex.LLM.RateLimiter do
  @moduledoc """
  Per-user rate limiting for LLM generation requests using ExRated.
  Limits differ by plan: free (10/h), pro (100/h), enterprise (1000/h).
  """

  @limits %{
    free: {10, 3_600_000},
    pro: {100, 3_600_000},
    enterprise: {1000, 3_600_000}
  }

  @spec check_rate(String.t(), atom()) :: :ok | {:error, :rate_limited}
  def check_rate(user_id, plan) do
    {limit, window} = Map.get(@limits, plan, {10, 3_600_000})
    bucket = "llm:#{user_id}"

    case ExRated.check_rate(bucket, window, limit) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end
end
