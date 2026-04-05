defmodule Blackboex.CodeGen.Sandbox do
  @moduledoc """
  Executes compiled modules in an isolated process with resource limits.

  Uses Task.Supervisor.async_nolink to run code in a separate process with
  max_heap_size enforcement and timeout protection.
  """

  alias Blackboex.Telemetry.Events

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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
    # Plug.Conn is tied to the HTTP process — it CANNOT be used from a
    # Task process (Bandit raises "Adapter functions must be called by
    # stream owner"). We run the Plug call in a linked Task that inherits
    # the caller's process group, then use Task.yield + Task.shutdown
    # for safe timeout handling (same pattern as execute/3).
    #
    # Previous approach used Process.exit(caller, :kill) which is
    # untrappable and would kill the Bandit stream owner process.
    plug_opts = module.init([])
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Tracer.with_span "blackboex.sandbox.execute" do
      start_time = System.monotonic_time(:millisecond)

      # Run the Plug call in a Task under the caller's process context.
      # The task inherits the caller's group leader, so conn adapter
      # calls (send_resp etc.) route back through the HTTP process.
      task =
        Task.async(fn ->
          try do
            result_conn = module.call(conn, plug_opts)
            {:ok, result_conn}
          rescue
            error ->
              {:exception, Exception.message(error)}
          end
        end)

      result =
        case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, {:ok, result_conn}} ->
            {:ok, result_conn}

          {:ok, {:exception, message}} ->
            {:error, {:exception, message}}

          {:exit, :killed} ->
            {:error, :memory_exceeded}

          {:exit, reason} ->
            {:error, {:runtime, reason}}

          nil ->
            {:error, :timeout}
        end

      duration_ms = System.monotonic_time(:millisecond) - start_time
      api_id = Keyword.get(opts, :api_id)
      Tracer.set_attributes([{"blackboex.api_id", api_id || "unknown"}])
      Events.emit_sandbox_execute(%{duration_ms: duration_ms, api_id: api_id})

      result
    end
  end

  defp run_sandboxed(fun, opts) do
    Tracer.with_span "blackboex.sandbox.execute" do
      start_time = System.monotonic_time(:millisecond)
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

      result =
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

      duration_ms = System.monotonic_time(:millisecond) - start_time
      api_id = Keyword.get(opts, :api_id)

      Tracer.set_attributes([{"blackboex.api_id", api_id || "unknown"}])

      Events.emit_sandbox_execute(%{duration_ms: duration_ms, api_id: api_id})

      result
    end
  end
end
