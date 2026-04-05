defmodule Blackboex.Testing.TestFormatterTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.TestFormatter

  setup do
    {:ok, pid} = GenServer.start_link(TestFormatter, [])
    %{pid: pid}
  end

  # ──────────────────────────────────────────────────────────────
  # get_results/1 — initial state
  # ──────────────────────────────────────────────────────────────

  describe "get_results/1 initial state" do
    test "returns empty list before any events", %{pid: pid} do
      assert TestFormatter.get_results(pid) == []
    end
  end

  # ──────────────────────────────────────────────────────────────
  # test_finished events
  # ──────────────────────────────────────────────────────────────

  describe "test_finished events" do
    test "collects a passing test", %{pid: pid} do
      test = build_test(name: :"test it works", state: nil, time: 5_000)
      GenServer.cast(pid, {:test_finished, test})

      results = TestFormatter.get_results(pid)

      assert length(results) == 1
      [result] = results
      assert result.name == "test it works"
      assert result.status == "passed"
      assert result.duration_ms == 5
      assert result.error == nil
    end

    test "collects a failed test with assertion error", %{pid: pid} do
      error = %ExUnit.AssertionError{
        left: 1,
        right: 2,
        message: "Assertion with == failed"
      }

      test = build_test(name: :"test math works", state: {:failed, [{nil, error}]}, time: 10_000)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.name == "test math works"
      assert result.status == "failed"
      assert result.error =~ "Expected: 1"
      assert result.error =~ "Got: 2"
      assert result.error =~ "Assertion with == failed"
    end

    test "collects a failed test with generic error", %{pid: pid} do
      error = %RuntimeError{message: "something went wrong"}
      test = build_test(name: :"test crashes", state: {:failed, [{nil, error}]}, time: 1_000)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.status == "failed"
      assert result.error =~ "something went wrong"
    end

    test "collects a failed test with unexpected error structure", %{pid: pid} do
      test = build_test(name: :"test weird", state: {:failed, [{nil, :some_atom}]}, time: 0)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.status == "failed"
      assert result.error =~ "some_atom"
    end

    test "collects an excluded test", %{pid: pid} do
      test = build_test(name: :"test excluded", state: {:excluded, "not in tag"}, time: 0)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.status == "excluded"
      assert result.error == nil
    end

    test "collects a skipped test", %{pid: pid} do
      test = build_test(name: :"test skipped", state: {:skipped, "skip reason"}, time: 0)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.status == "skipped"
      assert result.error == nil
    end

    test "collects an invalid test", %{pid: pid} do
      test = build_test(name: :"test invalid", state: {:invalid, "some reason"}, time: 0)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.status == "error"
      assert result.error == nil
    end

    test "preserves order of tests (first in, first out)", %{pid: pid} do
      for i <- 1..5 do
        test = build_test(name: :"test #{i}", state: nil, time: i * 1_000)
        GenServer.cast(pid, {:test_finished, test})
      end

      results = TestFormatter.get_results(pid)

      names = Enum.map(results, & &1.name)
      assert names == ["test 1", "test 2", "test 3", "test 4", "test 5"]
    end

    test "duration_ms truncates microseconds", %{pid: pid} do
      # 1500 microseconds = 1.5ms, div by 1000 = 1ms
      test = build_test(name: :"test timing", state: nil, time: 1_500)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.duration_ms == 1
    end

    test "duration_ms is 0 for very fast tests", %{pid: pid} do
      test = build_test(name: :"test fast", state: nil, time: 500)
      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.duration_ms == 0
    end

    test "handles multiple failures in a single test", %{pid: pid} do
      error1 = %ExUnit.AssertionError{left: :a, right: :b, message: "first assertion"}
      error2 = %ExUnit.AssertionError{left: 1, right: 2, message: "second assertion"}

      test =
        build_test(
          name: :"test multi-fail",
          state: {:failed, [{nil, error1}, {nil, error2}]},
          time: 0
        )

      GenServer.cast(pid, {:test_finished, test})

      [result] = TestFormatter.get_results(pid)

      assert result.error =~ "first assertion"
      assert result.error =~ "second assertion"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Other events (should not affect results)
  # ──────────────────────────────────────────────────────────────

  describe "non-test events" do
    test "suite_started doesn't affect results", %{pid: pid} do
      GenServer.cast(pid, {:suite_started, %{}})
      assert TestFormatter.get_results(pid) == []
    end

    test "suite_finished doesn't affect results", %{pid: pid} do
      GenServer.cast(pid, {:suite_finished, %{}})
      assert TestFormatter.get_results(pid) == []
    end

    test "module_started doesn't affect results", %{pid: pid} do
      GenServer.cast(pid, {:module_started, %{}})
      assert TestFormatter.get_results(pid) == []
    end

    test "module_finished doesn't affect results", %{pid: pid} do
      GenServer.cast(pid, {:module_finished, %{}})
      assert TestFormatter.get_results(pid) == []
    end

    test "unknown events don't crash the server", %{pid: pid} do
      GenServer.cast(pid, {:totally_unknown_event, %{data: "stuff"}})
      GenServer.cast(pid, :weird_atom)

      # Should still be alive and working
      assert TestFormatter.get_results(pid) == []
    end
  end

  # ──────────────────────────────────────────────────────────────
  # get_results/1 idempotency
  # ──────────────────────────────────────────────────────────────

  describe "get_results/1 idempotency" do
    test "can be called multiple times without clearing results", %{pid: pid} do
      test = build_test(name: :"test persist", state: nil, time: 0)
      GenServer.cast(pid, {:test_finished, test})

      assert length(TestFormatter.get_results(pid)) == 1
      assert length(TestFormatter.get_results(pid)) == 1
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  defp build_test(opts) do
    name = Keyword.fetch!(opts, :name)
    state = Keyword.fetch!(opts, :state)
    time = Keyword.fetch!(opts, :time)

    %ExUnit.Test{
      name: name,
      case: TestFormatterTestModule,
      module: TestFormatterTestModule,
      state: state,
      time: time,
      tags: %{
        test: name,
        module: TestFormatterTestModule,
        file: "test/test_formatter_test.exs",
        line: 1,
        describe: nil
      }
    }
  end
end
