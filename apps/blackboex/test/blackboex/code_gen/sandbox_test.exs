defmodule Blackboex.CodeGen.SandboxTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.Sandbox

  # We'll create real compiled modules for sandbox testing
  defmodule NormalHandler do
    def call(params) do
      x = Map.get(params, "a", 0)
      y = Map.get(params, "b", 0)
      %{result: x + y}
    end
  end

  defmodule InfiniteLoopHandler do
    def call(_params) do
      loop()
    end

    defp loop, do: loop()
  end

  defmodule MemoryHogHandler do
    def call(_params) do
      # Allocate a huge list to exceed heap limit
      build_list([], 10_000_000)
    end

    defp build_list(acc, 0), do: acc
    defp build_list(acc, n), do: build_list([n | acc], n - 1)
  end

  defmodule RuntimeErrorHandler do
    def call(_params) do
      _ = 1 / 0
    end
  end

  defmodule ExceptionHandler do
    def call(_params) do
      raise "something went wrong"
    end
  end

  describe "execute/3" do
    test "executes normal function and returns result" do
      assert {:ok, %{result: 3}} = Sandbox.execute(NormalHandler, %{"a" => 1, "b" => 2})
    end

    test "returns :timeout for infinite loop" do
      assert {:error, :timeout} = Sandbox.execute(InfiniteLoopHandler, %{}, timeout: 1000)
    end

    @tag :capture_log
    test "returns :memory_exceeded for excessive allocation" do
      assert {:error, :memory_exceeded} = Sandbox.execute(MemoryHogHandler, %{})
    end

    test "returns runtime error for division by zero" do
      assert {:error, {:exception, _message}} = Sandbox.execute(RuntimeErrorHandler, %{})
    end

    test "returns exception for raised errors" do
      assert {:error, {:exception, message}} = Sandbox.execute(ExceptionHandler, %{})
      assert message =~ "something went wrong"
    end

    test "caller process survives sandbox failure" do
      me = self()
      assert Process.alive?(me)

      assert {:error, :timeout} = Sandbox.execute(InfiniteLoopHandler, %{}, timeout: 500)

      # Caller still alive
      assert Process.alive?(me)
    end

    test "respects custom timeout option" do
      # Short timeout should trigger before the loop would naturally end
      assert {:error, :timeout} = Sandbox.execute(InfiniteLoopHandler, %{}, timeout: 100)
    end

    test "handles empty params" do
      assert {:ok, %{result: 0}} = Sandbox.execute(NormalHandler, %{})
    end

    test "handles params with various types" do
      params = %{"a" => 10, "b" => 20}
      assert {:ok, %{result: 30}} = Sandbox.execute(NormalHandler, params)
    end

    test "concurrent sandbox executions don't interfere" do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            Sandbox.execute(NormalHandler, %{"a" => i, "b" => i})
          end)
        end

      results = Task.await_many(tasks, 5_000)

      for {result, i} <- Enum.with_index(results, 1) do
        assert {:ok, %{result: expected}} = result
        assert expected == i * 2
      end
    end

    test "exception message is captured correctly" do
      assert {:error, {:exception, msg}} = Sandbox.execute(ExceptionHandler, %{})
      assert msg == "something went wrong"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # execute_plug/3
  # ──────────────────────────────────────────────────────────────

  defmodule NormalPlug do
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      Plug.Conn.send_resp(conn, 200, ~s|{"status": "ok"}|)
    end
  end

  defmodule SlowPlug do
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(_conn, _opts) do
      Process.sleep(:infinity)
    end
  end

  defmodule CrashingPlug do
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(_conn, _opts) do
      raise "plug crashed"
    end
  end

  describe "execute_plug/3" do
    test "executes normal plug and returns conn" do
      conn = Plug.Test.conn(:get, "/test")
      assert {:ok, result_conn} = Sandbox.execute_plug(NormalPlug, conn)
      assert result_conn.status == 200
      assert result_conn.resp_body == ~s|{"status": "ok"}|
    end

    test "returns exception for crashing plug" do
      conn = Plug.Test.conn(:get, "/test")
      assert {:error, {:exception, msg}} = Sandbox.execute_plug(CrashingPlug, conn)
      assert msg =~ "plug crashed"
    end

    test "returns timeout for slow plug" do
      conn = Plug.Test.conn(:get, "/test")

      # execute_plug runs in the CURRENT process with a watchdog.
      # The watchdog kills the caller process on timeout, so we must
      # run this in a spawned process and monitor it.
      test_pid = self()

      {pid, ref} =
        spawn_monitor(fn ->
          result = Sandbox.execute_plug(SlowPlug, conn, timeout: 200)
          send(test_pid, {:plug_result, result})
        end)

      # Either we get a result (if catch works) or the process dies (killed by watchdog)
      receive do
        {:plug_result, result} ->
          assert result == {:error, :timeout}

        {:DOWN, ^ref, :process, ^pid, reason} ->
          # Process was killed by watchdog — this IS the timeout behavior
          assert reason == :killed
      after
        3_000 ->
          flunk("Timed out waiting for plug execution")
      end
    end
  end
end
