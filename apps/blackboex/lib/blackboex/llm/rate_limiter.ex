defmodule Blackboex.LLM.RateLimiter do
  @moduledoc """
  Per-user rate limiting for LLM generation requests using ExRated.

  Limits per organization plan:

  | Plan | Requests/hour |
  |------|--------------|
  | `:free` | 10 |
  | `:pro` | 100 |
  | `:enterprise` | 1_000 |
  """

  @hour_ms 3_600_000

  @aggregate_limits %{
    free: {10, @hour_ms},
    pro: {100, @hour_ms},
    enterprise: {1000, @hour_ms}
  }

  @spec check_rate(String.t(), atom()) :: :ok | {:error, :rate_limited}
  def check_rate(user_id, plan) do
    bucket = "llm:#{user_id}"
    {limit, window} = Map.get(@aggregate_limits, plan, {10, @hour_ms})

    case ExRated.check_rate(bucket, window, limit) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end
end
