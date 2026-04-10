defmodule Blackboex.FlowExecutor.Nodes.BranchGateTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.BranchGate

  # ── Test impl modules ──────────────────────────────────────

  defmodule FakeStep do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, options) do
      value = Keyword.get(options, :return_value, "executed")
      {:ok, %{output: value, state: arguments[:prev_result][:state] || %{}}}
    end

    @impl true
    def compensate(_reason, _arguments, _context, _options), do: :retry

    @impl true
    def backoff(_reason, _arguments, _context, _options), do: 1_000
  end

  defmodule NoCompensateStep do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, "ok"}
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp skipped_args(state \\ %{}),
    do: %{prev_result: %{output: :__branch_skipped__, state: state}}

  defp normal_args(input \\ "hello", state \\ %{}),
    do: %{prev_result: %{output: input, state: state}}

  defp gate_opts(impl \\ FakeStep, impl_options \\ []),
    do: [impl: impl, impl_options: impl_options]

  # ── run/3 — skip detection ─────────────────────────────────

  describe "run/3 — branch skipped" do
    test "returns skipped sentinel without calling impl" do
      args = skipped_args(%{"key" => "val"})
      opts = gate_opts()

      assert {:ok, result} = BranchGate.run(args, %{}, opts)
      assert result.output == :__branch_skipped__
      assert result.state == %{"key" => "val"}
    end

    test "preserves state from skipped branch" do
      state = %{"a" => 1, "b" => 2}
      args = skipped_args(state)
      opts = gate_opts()

      assert {:ok, result} = BranchGate.run(args, %{}, opts)
      assert result.state == state
    end
  end

  # ── run/3 — delegation ─────────────────────────────────────

  describe "run/3 — delegation to impl" do
    test "delegates to impl when input is not skipped" do
      args = normal_args("real-input")
      opts = gate_opts(FakeStep, return_value: "custom")

      assert {:ok, result} = BranchGate.run(args, %{}, opts)
      assert result.output == "custom"
    end

    test "passes context through to impl" do
      args = normal_args()
      context = %{execution_id: "exec-1"}
      opts = gate_opts()

      # FakeStep doesn't use context, but this verifies no crash
      assert {:ok, _} = BranchGate.run(args, context, opts)
    end

    test "passes impl_options through to impl" do
      args = normal_args()
      opts = gate_opts(FakeStep, return_value: "via-opts")

      assert {:ok, result} = BranchGate.run(args, %{}, opts)
      assert result.output == "via-opts"
    end
  end

  # ── compensate/4 — delegation ──────────────────────────────

  describe "compensate/4" do
    test "delegates to impl when impl exports compensate/4" do
      result = BranchGate.compensate("error", %{}, %{}, gate_opts(FakeStep))
      assert result == :retry
    end

    test "returns :ok when impl does not export compensate/4" do
      result = BranchGate.compensate("error", %{}, %{}, gate_opts(NoCompensateStep))
      assert result == :ok
    end
  end

  # ── backoff/4 — delegation ─────────────────────────────────

  describe "backoff/4" do
    test "delegates to impl when impl exports backoff/4" do
      result = BranchGate.backoff("error", %{}, %{}, gate_opts(FakeStep))
      assert result == 1_000
    end

    test "returns :now when impl does not export backoff/4" do
      result = BranchGate.backoff("error", %{}, %{}, gate_opts(NoCompensateStep))
      assert result == :now
    end
  end

  # ── undo/4 — delegation ────────────────────────────────────

  describe "undo/4" do
    test "delegates undo to inner impl when impl exports undo/4" do
      # ElixirCode has undo/4
      value = %{output: "result", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}

      opts = [
        impl: Blackboex.FlowExecutor.Nodes.ElixirCode,
        impl_options: [undo_code: ~s|{input, state, result}|, timeout_ms: 5_000]
      ]

      assert :ok = BranchGate.undo(value, args, %{}, opts)
    end

    test "returns :ok when impl does not export undo/4" do
      # Start node has no undo/4
      value = %{output: "result", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}
      opts = [impl: Blackboex.FlowExecutor.Nodes.Start, impl_options: []]

      assert :ok = BranchGate.undo(value, args, %{}, opts)
    end
  end
end
