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
  end
end
