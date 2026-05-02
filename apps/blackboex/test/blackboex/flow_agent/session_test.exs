defmodule Blackboex.FlowAgent.SessionTest do
  use Blackboex.DataCase, async: false

  # The Session GenServer + Task.Supervisor lifecycle can race with sandbox
  # teardown — and several tests exercise failure paths that log warn/error.
  # Capture all log output for this module so the suite stays quiet.
  @moduletag :capture_log

  import Mox

  alias Blackboex.FlowAgent.Session
  alias Blackboex.FlowConversations

  setup :set_mox_global
  setup [:create_user_and_org]

  defp base_opts(%{user: user, org: org}) do
    flow = flow_fixture(%{user: user, org: org})
    conv = flow_conversation_fixture(%{flow: flow})
    run = flow_run_fixture(%{conversation: conv, user: user})

    %{
      run_id: run.id,
      flow_id: flow.id,
      conversation_id: conv.id,
      organization_id: org.id,
      user_id: user.id,
      run_type: :edit,
      trigger_message: "edit this flow",
      definition_before: %{}
    }
  end

  describe "registry" do
    test "session registers under SessionRegistry with run_id as key", ctx do
      opts = base_opts(ctx)

      # Block LLM so the Session is still alive when we query the registry.
      parent = self()

      Mox.stub(Blackboex.LLM.ClientMock, :stream_text, fn _p, _o ->
        send(parent, :llm_called)

        receive do
          :release -> :ok
        after
          1_000 -> :ok
        end

        {:ok, Stream.map([], & &1)}
      end)

      Mox.stub(Blackboex.LLM.ClientMock, :generate_text, fn _p, _o ->
        send(parent, :llm_called)

        receive do
          :release -> :ok
        after
          1_000 -> :ok
        end

        {:ok, %{content: "", usage: %{}}}
      end)

      {:ok, pid} = Session.start(opts)
      Process.monitor(pid)

      # Wait for LLM call to start — at that point the GenServer is registered.
      assert_receive :llm_called, 2_000

      [{registered_pid, _}] = Registry.lookup(Blackboex.FlowAgent.SessionRegistry, opts.run_id)
      assert registered_pid == pid

      # Let it finish naturally.
      assert_receive {:DOWN, _, :process, ^pid, :normal}, 3_000
    end
  end

  describe "lifecycle" do
    test "marks run as running when chain starts", ctx do
      opts = base_opts(ctx)

      # Block the LLM so we can observe the intermediate running state.
      parent = self()

      Mox.stub(Blackboex.LLM.ClientMock, :stream_text, fn _p, _o ->
        send(parent, :llm_called)
        # Simulate a slow stream
        Process.sleep(200)
        {:ok, Stream.map([], & &1)}
      end)

      Mox.stub(Blackboex.LLM.ClientMock, :generate_text, fn _p, _o ->
        send(parent, :llm_called)
        Process.sleep(200)
        {:ok, %{content: "", usage: %{}}}
      end)

      {:ok, _pid} = Session.start(opts)
      assert_receive :llm_called, 1_000

      # Run should be marked running by the time the LLM call starts
      reloaded_run = FlowConversations.get_run!(opts.run_id)
      assert reloaded_run.status == "running"
    end

    test "completes as :explain when LLM returns prose (no json fence)", ctx do
      opts = base_opts(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{opts.run_id}")

      Mox.stub(Blackboex.LLM.ClientMock, :stream_text, fn _p, _o ->
        {:ok, Stream.map(["Resposta: esse fluxo é assim."], &{:token, &1})}
      end)

      Mox.stub(Blackboex.LLM.ClientMock, :generate_text, fn _p, _o ->
        {:ok, %{content: "Resposta: esse fluxo é assim.", usage: %{}}}
      end)

      {:ok, _pid} = Session.start(opts)

      assert_receive {:run_completed, %{kind: :explain, answer: answer}}, 3_000
      assert answer =~ "esse fluxo"

      reloaded_run = FlowConversations.get_run!(opts.run_id)
      assert reloaded_run.status == "completed"
      assert reloaded_run.definition_after == nil
    end

    test "fails run when LLM returns truly empty content", ctx do
      opts = base_opts(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{opts.run_id}")

      Mox.stub(Blackboex.LLM.ClientMock, :stream_text, fn _p, _o ->
        {:ok, Stream.map([], & &1)}
      end)

      Mox.stub(Blackboex.LLM.ClientMock, :generate_text, fn _p, _o ->
        {:ok, %{content: "", usage: %{}}}
      end)

      {:ok, _pid} = Session.start(opts)

      assert_receive {:run_failed, %{reason: _}}, 3_000

      reloaded_run = FlowConversations.get_run!(opts.run_id)
      assert reloaded_run.status == "failed"
    end
  end
end
