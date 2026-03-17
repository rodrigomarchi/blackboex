defmodule Blackboex.CodeGen.Sandbox do
  @moduledoc """
  Executes compiled modules in an isolated process with resource limits.

  Uses Task.Supervisor.async_nolink to run code in a separate process with
  max_heap_size enforcement and timeout protection.
  """

  require Logger

  @default_timeout 5_000
  @default_max_heap_size 10_000_000

  @spec execute(module(), map(), keyword()) ::
          {:ok, term()}
          | {:error, :timeout}
          | {:error, :memory_exceeded}
          | {:error, {:runtime, term()}}
          | {:error, {:exception, String.t()}}
  def execute(module, params, opts \\ []) do
    run_sandboxed(fn -> module.call(params) end, opts)
  end

  @spec execute_plug(module(), Plug.Conn.t(), keyword()) ::
          {:ok, Plug.Conn.t()}
          | {:error, :timeout}
          | {:error, :memory_exceeded}
          | {:error, {:runtime, term()}}
          | {:error, {:exception, String.t()}}
  def execute_plug(module, conn, opts \\ []) do
    plug_opts = module.init([])
    run_sandboxed(fn -> module.call(conn, plug_opts) end, opts)
  end

  defp run_sandboxed(fun, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_heap = Keyword.get(opts, :max_heap_size, @default_max_heap_size)

    task =
      Task.Supervisor.async_nolink(
        Blackboex.SandboxTaskSupervisor,
        fn ->
          Process.flag(:max_heap_size, %{size: max_heap, kill: true, error_logger: true})

          try do
            {:ok, fun.()}
          rescue
            error ->
              {:exception, Exception.message(error)}
          end
        end
      )

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:exception, message}} ->
        {:error, {:exception, message}}

      {:exit, :killed} ->
        {:error, :memory_exceeded}

      {:exit, reason} ->
        {:error, {:runtime, reason}}

      nil ->
        {:error, :timeout}
    end
  end
end
