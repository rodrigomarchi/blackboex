defmodule Blackboex.FlowExecutor.Nodes.CompensateTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.{Condition, ElixirCode}

  describe "ElixirCode.compensate/4" do
    test "returns :retry for ErlangError timeout" do
      reason = %ErlangError{original: :timeout}

      assert :retry = ElixirCode.compensate(reason, %{}, %{}, [])
    end

    test "returns :retry for string timeout message" do
      reason = "execution timed out after 5000ms"

      assert :retry = ElixirCode.compensate(reason, %{}, %{}, [])
    end

    test "returns :ok for logic error (string)" do
      reason = "argument error"

      assert :ok = ElixirCode.compensate(reason, %{}, %{}, [])
    end

    test "returns :ok for exception struct (logic error)" do
      reason = %RuntimeError{message: "bad value"}

      assert :ok = ElixirCode.compensate(reason, %{}, %{}, [])
    end

    test "returns :ok for arbitrary reason" do
      assert :ok = ElixirCode.compensate(:some_error, %{}, %{}, [])
    end
  end

  describe "Condition.compensate/4" do
    test "returns :retry for ErlangError timeout" do
      reason = %ErlangError{original: :timeout}

      assert :retry = Condition.compensate(reason, %{}, %{}, [])
    end

    test "returns :retry for string timeout message" do
      reason = "execution timed out after 5000ms"

      assert :retry = Condition.compensate(reason, %{}, %{}, [])
    end

    test "returns :ok for logic error (string)" do
      reason = "condition expression must return a non-negative integer, got: nil"

      assert :ok = Condition.compensate(reason, %{}, %{}, [])
    end

    test "returns :ok for arbitrary reason" do
      assert :ok = Condition.compensate(:some_error, %{}, %{}, [])
    end
  end

  describe "ElixirCode.backoff/4" do
    test "returns 500ms for first retry (retry_count 0)" do
      assert 500 = ElixirCode.backoff(:timeout, %{}, %{}, [])
    end

    test "returns 1000ms for retry_count 1" do
      assert 1_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 1}, [])
    end

    test "returns 2000ms for retry_count 2" do
      assert 2_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 2}, [])
    end

    test "returns 4000ms for retry_count 3" do
      assert 4_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 3}, [])
    end

    test "returns 8000ms for retry_count 4" do
      assert 8_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 4}, [])
    end

    test "caps at 10000ms for retry_count 5" do
      assert 10_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 5}, [])
    end

    test "caps at 10000ms for large retry_count" do
      assert 10_000 = ElixirCode.backoff(:timeout, %{}, %{current_try: 20}, [])
    end
  end

  describe "Condition.backoff/4" do
    test "returns 500ms for first retry (retry_count 0)" do
      assert 500 = Condition.backoff(:timeout, %{}, %{}, [])
    end

    test "returns 1000ms for retry_count 1" do
      assert 1_000 = Condition.backoff(:timeout, %{}, %{current_try: 1}, [])
    end

    test "returns 2000ms for retry_count 2" do
      assert 2_000 = Condition.backoff(:timeout, %{}, %{current_try: 2}, [])
    end

    test "caps at 10000ms for retry_count 5" do
      assert 10_000 = Condition.backoff(:timeout, %{}, %{current_try: 5}, [])
    end

    test "caps at 10000ms for large retry_count" do
      assert 10_000 = Condition.backoff(:timeout, %{}, %{current_try: 20}, [])
    end
  end
end
