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
    # Always reset circuit breaker so prior tests don't affect this one
    Blackboex.LLM.CircuitBreaker.reset(:anthropic)

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

  # ── circuit breaker open tests ───────────────────────────────────

  describe "handle_info(:start_chain) when circuit breaker is open" do
    setup :setup_test_data

    test "marks run as failed with circuit breaker message", context do
      # Trip the circuit breaker by recording enough failures
      for _ <- 1..5, do: Blackboex.LLM.CircuitBreaker.record_failure(:anthropic)

      # Verify the circuit is now open
      refute Blackboex.LLM.CircuitBreaker.allow?(:anthropic)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{context.run.id}")

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)

      # GenServer should stop almost immediately because circuit is open
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "failed"
      assert updated_run.error_summary =~ "circuit breaker"
    end

    test "broadcasts :agent_failed when circuit is open", context do
      for _ <- 1..5, do: Blackboex.LLM.CircuitBreaker.record_failure(:anthropic)

      run_id = context.run.id
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      assert_receive {:agent_failed, %{error: error_msg, run_id: ^run_id}}
      assert error_msg =~ "unavailable"
    end

    test "persists circuit breaker error event", context do
      for _ <- 1..5, do: Blackboex.LLM.CircuitBreaker.record_failure(:anthropic)

      {:ok, pid} = Session.start(build_session_opts(context))
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      events = Conversations.list_events(context.run.id)
      error_event = Enum.find(events, &(&1.event_type == "error"))
      assert error_event != nil
      assert error_event.content =~ "Circuit breaker"
    end
  end

  # ── retries_exceeded and unknown messages ────────────────────────

  describe "handle_info for non-critical messages" do
    setup :setup_test_data

    test ":retries_exceeded does not crash the GenServer", context do
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
      assert_receive :llm_called, 5_000

      # Send :retries_exceeded — should not crash
      send(pid, :retries_exceeded)

      # GenServer should still be alive
      Process.sleep(100)
      assert Process.alive?(pid)

      # Clean up: trigger timeout to stop the GenServer
      send(pid, :task_timeout)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
    end

    test "unknown messages are ignored without crashing", context do
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
      assert_receive :llm_called, 5_000

      # Various unexpected messages
      send(pid, :totally_unknown_message)
      send(pid, {:unexpected, :tuple})
      send(pid, %{random: "map"})

      Process.sleep(100)
      assert Process.alive?(pid)

      send(pid, :task_timeout)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
    end
  end

  # ── chain success variations ─────────────────────────────────────

  describe "handle_info with task success variations" do
    setup :setup_test_data

    test "partial result sets status to 'partial'", context do
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

      # Send result with partial: true
      send(pid, {fake_ref, {:ok, %{code: "def handle(_), do: :ok", partial: true, summary: "Partial result", usage: %{}}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "partial"
    end

    test "success result persists final_code and run_summary", context do
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

      code = "def handle(params), do: %{status: 200, body: params}"
      test_code = "test \"it works\" do\n  assert true\nend"

      send(pid, {fake_ref, {:ok, %{code: code, test_code: test_code, summary: "Generated calculator", usage: %{input_tokens: 100, output_tokens: 200}}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "completed"
      assert updated_run.final_code == code
      assert updated_run.final_test_code == test_code
      assert updated_run.run_summary == "Generated calculator"
    end

    test "success broadcasts :agent_completed with code and summary", context do
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

      fake_ref = make_ref()

      :sys.replace_state(pid, fn state ->
        if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
        %{state | task_ref: fake_ref, timeout_timer: nil}
      end)

      send(pid, {fake_ref, {:ok, %{code: "def handle(_), do: :ok", summary: "Done", usage: %{}}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      assert_receive {:agent_completed, %{code: "def handle(_), do: :ok", summary: "Done", run_id: ^run_id, status: "completed"}}
    end

    test "success with nil usage defaults to zero tokens", context do
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

      # No :usage key in result
      send(pid, {fake_ref, {:ok, %{code: "def handle(_), do: :ok", summary: "ok"}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.input_tokens == 0
      assert updated_run.output_tokens == 0
    end
  end

  # ── chain failure variations ─────────────────────────────────────

  describe "handle_info with task error variations" do
    setup :setup_test_data

    test "error with map containing :message key uses the message", context do
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

      send(pid, {fake_ref, {:error, %{message: "Rate limit exceeded"}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.status == "failed"
      assert updated_run.error_summary == "Rate limit exceeded"
    end

    test "error with atom reason formats as inspect", context do
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

      send(pid, {fake_ref, {:error, :api_not_found}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      updated_run = Conversations.get_run!(context.run.id)
      assert updated_run.error_summary == ":api_not_found"
    end

    test "failure sets API generation_status to 'failed'", context do
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

      send(pid, {fake_ref, {:error, "something broke"}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      api = Apis.get_api(context.org.id, context.api.id)
      assert api.generation_status == "failed"
      assert api.generation_error =~ "something broke"
      assert api.validation_report["overall"] == "fail"
    end

    test "failure truncates long error messages to 5000 chars in API", context do
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

      long_error = String.duplicate("x", 10_000)
      send(pid, {fake_ref, {:error, long_error}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      api = Apis.get_api(context.org.id, context.api.id)
      assert String.length(api.generation_error) <= 5000
    end
  end

  # ── edit run type ────────────────────────────────────────────────

  describe "edit run type" do
    setup :setup_test_data

    test "stores current_code and current_tests in state and completes as edit", context do
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(:infinity)
      end)

      # Create an edit run
      {:ok, edit_run} =
        Conversations.create_run(%{
          conversation_id: context.conversation.id,
          api_id: context.api.id,
          user_id: context.user.id,
          organization_id: context.org.id,
          run_type: "edit",
          trigger_message: "Add input validation"
        })

      {:ok, edit_run} = Conversations.update_run_metrics(edit_run, %{started_at: DateTime.utc_now()})

      opts =
        build_session_opts(context)
        |> Map.merge(%{
          run_id: edit_run.id,
          run_type: "edit",
          trigger_message: "Add input validation",
          current_code: "def handle(p), do: p",
          current_tests: "test \"basic\" do end"
        })

      {:ok, pid} = Session.start(opts)
      ref = Process.monitor(pid)

      # Wait for chain execution to start (LLM called or timeout to settle)
      receive do
        :llm_called -> :ok
      after
        2_000 -> :ok
      end

      # Verify state stores the edit fields via :sys.get_state
      if Process.alive?(pid) do
        state = :sys.get_state(pid)
        assert state.run_type == "edit"
        assert state.current_code == "def handle(p), do: p"
        assert state.current_tests == "test \"basic\" do end"
        assert state.trigger_message == "Add input validation"

        # Clean up
        fake_ref = make_ref()

        :sys.replace_state(pid, fn s ->
          if s.timeout_timer, do: Process.cancel_timer(s.timeout_timer)
          %{s | task_ref: fake_ref, timeout_timer: nil}
        end)

        send(pid, {fake_ref, {:ok, %{code: "def handle(p), do: p", summary: "edited", usage: %{}}}})
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      else
        # Process already stopped — still verify the run type is correct
        :ok
      end

      updated_run = Conversations.get_run!(edit_run.id)
      assert updated_run.run_type == "edit"
    end
  end

  # ── conversation stats ───────────────────────────────────────────

  describe "conversation stats update" do
    setup :setup_test_data

    test "increments conversation total_runs on success", context do
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

      send(pid, {fake_ref, {:ok, %{code: "def handle(_), do: :ok", summary: "ok", usage: %{}}}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      conversation = Conversations.get_conversation(context.conversation.id)
      assert conversation.total_runs >= 1
    end

    test "increments conversation total_runs on failure too", context do
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

      send(pid, {fake_ref, {:error, "some failure"}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

      conversation = Conversations.get_conversation(context.conversation.id)
      assert conversation.total_runs >= 1
    end
  end

  # ── init/1 ───────────────────────────────────────────────────────

  describe "init/1" do
    setup :setup_test_data

    test "sends :start_chain on init", context do
      # We can verify this by checking that the GenServer immediately starts
      # working (calling LLM) after being started
      test_pid = self()

      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        send(test_pid, :chain_started)
        Process.sleep(:infinity)
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        send(test_pid, :chain_started)
        Process.sleep(:infinity)
      end)

      {:ok, pid} = Session.start(build_session_opts(context))

      # Chain execution begins automatically (triggered by send(self(), :start_chain) in init)
      assert_receive :chain_started, 5_000

      send(pid, :task_timeout)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
    end
  end

  # ── child_spec/1 ─────────────────────────────────────────────────

  describe "child_spec/1" do
    test "returns correct child spec with temporary restart" do
      opts = %{run_id: "test-run-123"}
      spec = Session.child_spec(opts)

      assert spec.id == {Session, "test-run-123"}
      assert spec.restart == :temporary
      assert spec.shutdown == 30_000
      assert spec.start == {Session, :start_link, [opts]}
    end
  end
end
