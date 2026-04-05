defmodule Blackboex.Agent.SessionTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration
  @moduletag :capture_log

  import Blackboex.AccountsFixtures
  import Mox

  alias Blackboex.Agent.Session
  alias Blackboex.Apis
  alias Blackboex.Conversations
  alias Blackboex.Organizations

  setup :set_mox_global
  setup :verify_on_exit!

  # Valid minimal source code so start_chain_execution can fetch the API and
  # reset validation_report without errors.
  @minimal_code """
  def handle(params) do
    %{status: 200, body: %{result: "ok"}}
  end
  """

  defp setup_test_data(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)

    {:ok, api} =
      Apis.create_api(%{
        name: "session-test-api-#{System.unique_integer([:positive])}",
        organization_id: org.id,
        user_id: user.id,
        source_code: @minimal_code
      })

    {:ok, conversation} = Conversations.get_or_create_conversation(api.id, org.id)

    {:ok, run} =
      Conversations.create_run(%{
        conversation_id: conversation.id,
        api_id: api.id,
        user_id: user.id,
        organization_id: org.id,
        run_type: "generation",
        trigger_message: "test prompt"
      })

    # Set started_at so complete_run can compute duration_ms without a nil crash.
    {:ok, run} = Conversations.update_run_metrics(run, %{started_at: DateTime.utc_now()})

    %{user: user, org: org, api: api, conversation: conversation, run: run}
  end

  defp build_session_opts(%{run: run, api: api, conversation: conversation, user: user, org: org}) do
    %{
      run_id: run.id,
      api_id: api.id,
      conversation_id: conversation.id,
      run_type: "generation",
      trigger_message: "test prompt",
      user_id: user.id,
      organization_id: org.id,
      current_code: nil,
      current_tests: nil
    }
  end

  # ── task_timeout tests ───────────────────────────────────────────

  describe "handle_info(:task_timeout, state)" do
    setup :setup_test_data

    test "marks run as failed with timeout error message", context do
      test_pid = self()

      # Mock stream_text to signal readiness, then block so the task never
      # completes and the GenServer stays alive long enough for us to send
      # :task_timeout.
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{context.run.id}")

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      # Wait until the task has actually started calling the LLM, confirming the
      # GenServer has set task_ref and timeout_timer in its state.
      assert_receive :llm_called, 5_000

      # Simulate the 7-minute timer firing.
      send(pid, :task_timeout)

      # GenServer must stop normally after handling the timeout.
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "failed"
      assert updated_run.error_summary =~ "timeout"
    end

    test "broadcasts :agent_failed on PubSub after timeout", context do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      run_id = context.run.id
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      assert_receive :llm_called, 5_000
      send(pid, :task_timeout)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      assert_receive {:agent_failed, %{error: error_msg, run_id: ^run_id}}
      assert error_msg =~ "timeout"
    end

    test "sets API validation_report overall to fail after timeout", context do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      assert_receive :llm_called, 5_000
      send(pid, :task_timeout)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      api = Apis.get_api(context.org.id, context.api.id)
      assert api.validation_report["overall"] == "fail"
    end
  end

  # ── timer cancellation tests ─────────────────────────────────────
  #
  # These tests verify that when the task completes (success or error) the
  # GenServer stops normally and the run ends in the correct terminal state —
  # NOT marked failed with the timeout message.  We avoid running the full
  # CodePipeline (which has heavy validation) by injecting a fake task_ref into
  # the GenServer state via :sys.replace_state and sending the task result
  # message directly to the process.

  describe "timer cancellation on task completion" do
    setup :setup_test_data

    test "successful task result marks run as completed and stops GenServer", context do
      test_pid = self()

      # Block the LLM so start_chain_execution sets up state but the task never
      # naturally completes — giving us time to replace state and inject our
      # own task result.
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      # Wait for the task to be running (so task_ref is set in state).
      assert_receive :llm_called, 5_000

      # Grab the real task_ref from the GenServer state, then cancel the
      # 7-minute timer so it cannot fire during the test.
      fake_ref = make_ref()

      :sys.replace_state(pid, fn state ->
        if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
        %{state | task_ref: fake_ref, timeout_timer: nil}
      end)

      # Simulate the task completing successfully.
      send(pid, {fake_ref, {:ok, %{code: "def handle(_), do: %{}", summary: "ok", usage: %{}}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status in ["completed", "partial"]
      refute is_binary(updated_run.error_summary) and updated_run.error_summary =~ "timeout"
    end

    test "task error result marks run as failed with error reason (not timeout)", context do
      # The first LLM call fails immediately; pipeline propagates {:error, ...}
      # back to the GenServer via the task result message.
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:error, "simulated LLM error"}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, "simulated LLM error"}
      end)

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "failed"
      # Error must come from the LLM failure, not the timeout handler.
      refute updated_run.error_summary =~ "timeout"
    end

    test "process DOWN message marks run as failed with crashed reason (not timeout)", context do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      assert_receive :llm_called, 5_000

      fake_ref = make_ref()

      :sys.replace_state(pid, fn state ->
        if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
        %{state | task_ref: fake_ref, timeout_timer: nil}
      end)

      # Simulate the task process crashing.
      send(pid, {:DOWN, fake_ref, :process, self(), :killed})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "failed"
      assert updated_run.error_summary =~ "crashed"
      refute updated_run.error_summary =~ "timeout"
    end
  end
end
