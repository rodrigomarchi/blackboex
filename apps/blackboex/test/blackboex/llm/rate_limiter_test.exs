defmodule Blackboex.LLM.RateLimiterTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Blackboex.LLM.RateLimiter

  setup do
    # Use a unique user_id per test to avoid cross-test interference
    user_id = Ecto.UUID.generate()
    %{user_id: user_id}
  end

  describe "check_rate/2" do
    test "allows generations within limit", %{user_id: user_id} do
      assert :ok = RateLimiter.check_rate(user_id, :free)
    end

    test "blocks after exceeding free limit", %{user_id: user_id} do
      for _ <- 1..10 do
        assert :ok = RateLimiter.check_rate(user_id, :free)
      end

      assert {:error, :rate_limited} = RateLimiter.check_rate(user_id, :free)
    end

    test "pro plan has higher limit", %{user_id: user_id} do
      for _ <- 1..10 do
        assert :ok = RateLimiter.check_rate(user_id, :pro)
      end

      # Pro should still allow after 10 (limit is 100)
      assert :ok = RateLimiter.check_rate(user_id, :pro)
    end
  end
end
