defmodule Blackboex.LLM.CircuitBreakerTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Blackboex.LLM.CircuitBreaker

  # We use the default __MODULE__ name, so tests can't be async.
  # Each test resets state via CircuitBreaker.reset/1.

  setup do
    # Ensure the CircuitBreaker is running (it's started by the application supervisor)
    # Reset any provider state from prior tests
    provider = :"test_provider_#{System.unique_integer([:positive])}"
    %{provider: provider}
  end

  # ──────────────────────────────────────────────────────────────
  # Initial state
  # ──────────────────────────────────────────────────────────────

  describe "initial state" do
    test "new provider starts in :closed state", %{provider: provider} do
      assert CircuitBreaker.get_state(provider) == :closed
    end

    test "new provider allows requests", %{provider: provider} do
      assert CircuitBreaker.allow?(provider) == true
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Closed state behavior
  # ──────────────────────────────────────────────────────────────

  describe "closed state" do
    test "allows requests", %{provider: provider} do
      assert CircuitBreaker.allow?(provider) == true
    end

    test "stays closed after fewer than 5 failures", %{provider: provider} do
      for _ <- 1..4 do
        CircuitBreaker.record_failure(provider)
      end

      # Give GenServer time to process casts
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :closed
      assert CircuitBreaker.allow?(provider) == true
    end

    test "transitions to :open after 5 failures within window", %{provider: provider} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :open
    end

    test "success resets failure count", %{provider: provider} do
      for _ <- 1..4 do
        CircuitBreaker.record_failure(provider)
      end

      CircuitBreaker.record_success(provider)
      :timer.sleep(10)

      # After success in closed state, failures are cleared
      # So one more failure should NOT open the circuit
      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :closed
    end

    test "5th failure at exact threshold opens circuit", %{provider: provider} do
      # 4 failures — still closed
      for _ <- 1..4 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :closed

      # 5th failure — opens
      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Open state behavior
  # ──────────────────────────────────────────────────────────────

  describe "open state" do
    setup %{provider: provider} do
      # Force open state
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open
      :ok
    end

    test "blocks requests", %{provider: provider} do
      assert CircuitBreaker.allow?(provider) == false
    end

    test "additional failures don't change state", %{provider: provider} do
      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :open
    end

    test "success while open doesn't change state", %{provider: provider} do
      # Success in :open state hits the _other catch-all, so state unchanged
      CircuitBreaker.record_success(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :open
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Half-open state behavior
  # ──────────────────────────────────────────────────────────────

  describe "half-open state" do
    test "allows requests", %{provider: provider} do
      force_half_open(provider)

      assert CircuitBreaker.allow?(provider) == true
    end

    test "transitions to :closed after 2 consecutive successes", %{provider: provider} do
      force_half_open(provider)

      CircuitBreaker.record_success(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :half_open

      CircuitBreaker.record_success(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :closed
    end

    test "transitions to :open on any failure", %{provider: provider} do
      force_half_open(provider)

      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :open
    end

    test "failure after 1 success resets back to :open", %{provider: provider} do
      force_half_open(provider)

      # 1 success — still half_open
      CircuitBreaker.record_success(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :half_open

      # Failure resets to open
      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Reset
  # ──────────────────────────────────────────────────────────────

  describe "reset/1" do
    test "resets open circuit to closed", %{provider: provider} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open

      CircuitBreaker.reset(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :closed
      assert CircuitBreaker.allow?(provider) == true
    end

    test "resets half-open circuit to closed", %{provider: provider} do
      force_half_open(provider)
      assert CircuitBreaker.get_state(provider) == :half_open

      CircuitBreaker.reset(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :closed
    end

    test "reset on already-closed is idempotent", %{provider: provider} do
      assert CircuitBreaker.get_state(provider) == :closed

      CircuitBreaker.reset(provider)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider) == :closed
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Multi-provider isolation
  # ──────────────────────────────────────────────────────────────

  describe "multi-provider isolation" do
    test "failures on one provider don't affect another" do
      provider_a = :"isolation_a_#{System.unique_integer([:positive])}"
      provider_b = :"isolation_b_#{System.unique_integer([:positive])}"

      # Open circuit for provider A
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider_a)
      end

      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider_a) == :open
      assert CircuitBreaker.get_state(provider_b) == :closed
      assert CircuitBreaker.allow?(provider_b) == true
    end

    test "reset on one provider doesn't affect another" do
      provider_a = :"reset_a_#{System.unique_integer([:positive])}"
      provider_b = :"reset_b_#{System.unique_integer([:positive])}"

      # Open both
      for provider <- [provider_a, provider_b], _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)

      # Reset only A
      CircuitBreaker.reset(provider_a)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(provider_a) == :closed
      assert CircuitBreaker.get_state(provider_b) == :open
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Full lifecycle
  # ──────────────────────────────────────────────────────────────

  describe "full lifecycle" do
    test "closed -> open -> half_open -> closed", %{provider: provider} do
      # Start closed
      assert CircuitBreaker.get_state(provider) == :closed

      # 5 failures -> open
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open

      # Force half-open by manipulating state directly
      force_half_open(provider)
      assert CircuitBreaker.get_state(provider) == :half_open

      # 2 successes -> closed
      CircuitBreaker.record_success(provider)
      CircuitBreaker.record_success(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :closed
    end

    test "closed -> open -> half_open -> open (probe failure)", %{provider: provider} do
      # 5 failures -> open
      for _ <- 1..5 do
        CircuitBreaker.record_failure(provider)
      end

      :timer.sleep(10)

      # Force half-open
      force_half_open(provider)
      assert CircuitBreaker.get_state(provider) == :half_open

      # Probe fails -> back to open
      CircuitBreaker.record_failure(provider)
      :timer.sleep(10)
      assert CircuitBreaker.get_state(provider) == :open
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  # Forces a provider into half_open state by directly manipulating GenServer state.
  # In production, this would happen via timer after recovery_timeout_ms (30s).
  defp force_half_open(provider) do
    :sys.replace_state(CircuitBreaker, fn state ->
      provider_state = %Blackboex.LLM.CircuitBreaker.ProviderState{
        state: :half_open,
        failures: [],
        consecutive_successes: 0,
        opened_at: System.monotonic_time(:millisecond) - 60_000
      }

      %{state | providers: Map.put(state.providers, provider, provider_state)}
    end)
  end
end
