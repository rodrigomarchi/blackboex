defmodule Blackboex.FlowExecutor.Nodes.WebhookWaitTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor.Nodes.WebhookWait

  # ── Helpers ─────────────────────────────────────────────────

  defp args_with(input, state \\ %{}),
    do: %{prev_result: %{output: input, state: state}}

  defp base_options(overrides \\ []) do
    Keyword.merge(
      [event_type: "approval", timeout_ms: 3_600_000, resume_path: ""],
      overrides
    )
  end

  # ── run/3 — halt behavior ──────────────────────────────────

  describe "run/3 — halt behavior" do
    test "returns {:halt, map} with event_type and input/state" do
      args = args_with(%{"name" => "test"}, %{"key" => "val"})
      opts = base_options()

      assert {:halt, halt_info} = WebhookWait.run(args, %{}, opts)
      assert halt_info.event_type == "approval"
      assert halt_info.input == %{"name" => "test"}
      assert halt_info.state == %{"key" => "val"}
    end

    test "includes resume_path in halt info" do
      args = args_with("input")
      opts = base_options(resume_path: "data.approved")

      assert {:halt, halt_info} = WebhookWait.run(args, %{}, opts)
      assert halt_info.resume_path == "data.approved"
    end

    test "includes execution_id from context" do
      args = args_with("input")
      opts = base_options()
      exec_id = Ecto.UUID.generate()
      context = %{execution_id: exec_id}

      assert {:halt, halt_info} = WebhookWait.run(args, context, opts)
      assert halt_info.execution_id == exec_id
    end

    test "execution_id is nil when not in context" do
      args = args_with("input")
      opts = base_options()

      assert {:halt, halt_info} = WebhookWait.run(args, %{}, opts)
      assert halt_info.execution_id == nil
    end
  end

  # ── run/3 — execution status update ────────────────────────

  describe "run/3 — execution status update" do
    test "sets execution status to halted when execution_id exists" do
      {user, org} = user_and_org_fixture()
      flow = flow_fixture(%{user: user, org: org})
      {:ok, execution} = FlowExecutions.create_execution(flow, %{})
      FlowExecutions.update_execution_status(execution, "running")

      args = args_with("input")
      opts = base_options()
      context = %{execution_id: execution.id}

      assert {:halt, _} = WebhookWait.run(args, context, opts)

      updated = FlowExecutions.get_execution(execution.id)
      assert updated.status == "halted"
    end

    test "does not crash when execution_id is nil" do
      args = args_with("input")
      opts = base_options()

      assert {:halt, _} = WebhookWait.run(args, %{}, opts)
    end

    test "does not crash when execution not found in DB" do
      args = args_with("input")
      opts = base_options()
      context = %{execution_id: Ecto.UUID.generate()}

      assert {:halt, _} = WebhookWait.run(args, context, opts)
    end
  end

  # ── run/3 — input extraction ───────────────────────────────

  describe "run/3 — input extraction" do
    test "extracts input and state from standard arguments" do
      args = args_with(%{"data" => 42}, %{"s" => true})
      opts = base_options()

      assert {:halt, halt_info} = WebhookWait.run(args, %{}, opts)
      assert halt_info.input == %{"data" => 42}
      assert halt_info.state == %{"s" => true}
    end

    test "handles empty state" do
      args = args_with("just-input")
      opts = base_options()

      assert {:halt, halt_info} = WebhookWait.run(args, %{}, opts)
      assert halt_info.input == "just-input"
      assert halt_info.state == %{}
    end
  end
end
