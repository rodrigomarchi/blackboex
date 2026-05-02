defmodule Blackboex.FlowAgent.ChainRunnerTest do
  use Blackboex.DataCase, async: true

  # Negative-path tests deliberately invoke handle_chain_failure paths that
  # log warnings/errors. Capture them so they don't pollute test output.
  @moduletag :capture_log

  alias Blackboex.FlowAgent.ChainRunner
  alias Blackboex.FlowAgent.Session
  alias Blackboex.FlowConversations
  alias Blackboex.Flows

  setup [:create_user_and_org]

  @good_definition %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 250},
        "data" => %{}
      },
      %{
        "id" => "n2",
        "type" => "end",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{}
      }
    ],
    "edges" => [
      %{
        "id" => "e1",
        "source" => "n1",
        "source_port" => 0,
        "target" => "n2",
        "target_port" => 0
      }
    ]
  }

  defp build_session(%{user: user, org: org}) do
    flow = flow_fixture(%{user: user, org: org})
    conv = flow_conversation_fixture(%{flow: flow})
    run = flow_run_fixture(%{conversation: conv, user: user})
    {:ok, _} = FlowConversations.mark_run_running(run)

    state = %Session{
      run_id: run.id,
      flow_id: flow.id,
      conversation_id: conv.id,
      organization_id: org.id,
      user_id: user.id,
      run_type: :edit,
      trigger_message: "edite",
      definition_before: %{}
    }

    %{state: state, flow: flow, conv: conv, run: run}
  end

  describe "handle_chain_success/2" do
    test "persists completed event, completes run, records ai edit, broadcasts run_completed",
         ctx do
      %{state: state, flow: flow, conv: conv, run: run} = build_session(ctx)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{run.id}")

      :ok =
        ChainRunner.handle_chain_success(state, %{
          kind: :edit,
          definition: @good_definition,
          summary: "pronto",
          input_tokens: 10,
          output_tokens: 20
        })

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.status == "completed"
      assert reloaded_run.definition_after == @good_definition
      assert reloaded_run.run_summary == "pronto"

      # Events contain a 'completed' entry
      events = FlowConversations.list_events(run.id)
      assert Enum.any?(events, &(&1.event_type == "completed"))

      # Flow.definition was updated
      reloaded_flow = Flows.get_flow(state.organization_id, flow.id)
      assert reloaded_flow.definition == @good_definition

      # Conversation stats incremented
      reloaded_conv = FlowConversations.get_conversation(conv.id)
      assert reloaded_conv.total_runs >= 1
      assert reloaded_conv.total_input_tokens >= 10

      # Broadcasts on both run topic and flow topic
      assert_receive {:run_completed, %{run_id: rid, definition: def}}, 500
      assert rid == run.id
      assert def == @good_definition
    end

    test "fails gracefully when record_ai_edit returns error", ctx do
      %{state: state, flow: flow, run: run} = build_session(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")

      # Passing a bad definition that BlackboexFlow.validate will reject → failure path
      bad = %{"version" => "9.99", "nodes" => [], "edges" => []}

      :ok =
        ChainRunner.handle_chain_success(state, %{
          kind: :edit,
          definition: bad,
          summary: "broken",
          input_tokens: 0,
          output_tokens: 0
        })

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.status == "failed"
      assert_receive {:run_failed, _payload}, 500
    end
  end

  describe "handle_chain_success/2 explain mode" do
    test "persists answer, completes run without definition_after, broadcasts kind :explain",
         ctx do
      %{state: state, flow: flow, run: run} = build_session(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")

      :ok =
        ChainRunner.handle_chain_success(state, %{
          kind: :explain,
          answer: "Esse fluxo valida evento e retorna status.",
          input_tokens: 5,
          output_tokens: 10
        })

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.status == "completed"
      # Edit did not happen — definition_after stays nil, flow unchanged
      assert reloaded_run.definition_after == nil
      assert reloaded_run.run_summary =~ "valida evento"

      # Flow definition remains the empty map that the fixture created
      reloaded_flow = Blackboex.Flows.get_flow(state.organization_id, flow.id)
      assert reloaded_flow.definition == %{}

      assert_receive {:run_completed, %{kind: :explain, answer: ans}}, 500
      assert ans =~ "valida evento"
    end
  end

  describe "handle_chain_failure/2" do
    test "appends failed event, fails run, broadcasts on both topics", ctx do
      %{state: state, flow: flow, run: run} = build_session(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{run.id}")

      :ok = ChainRunner.handle_chain_failure(state, "boom")

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.status == "failed"
      assert reloaded_run.error_message == "boom"

      events = FlowConversations.list_events(run.id)
      assert Enum.any?(events, &(&1.event_type == "failed"))

      assert_receive {:run_failed, %{reason: "boom"}}, 500
    end

    test "formats {:crashed, reason} tuples", ctx do
      %{state: state, run: run} = build_session(ctx)

      :ok = ChainRunner.handle_chain_failure(state, {:crashed, :badarg})

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.error_message =~ "crashou"
    end

    test "formats {:invalid_flow, reason} tuples", ctx do
      %{state: state, run: run} = build_session(ctx)

      :ok = ChainRunner.handle_chain_failure(state, {:invalid_flow, "missing start node"})

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.error_message =~ "Fluxo inválido"
      assert reloaded_run.error_message =~ "missing start"
    end
  end

  describe "handle_chain_failure/2 resilience" do
    test "broadcasts :run_failed even if DB persistence crashes", ctx do
      %{state: state, flow: flow} = build_session(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")

      # Simulate DB-unreachable scenario by stuffing a bogus run_id into state
      # — get_run! will raise. The rescue clause must still broadcast.
      broken_state = %{state | run_id: Ecto.UUID.generate()}

      :ok = ChainRunner.handle_chain_failure(broken_state, "boom")

      assert_receive {:run_failed, %{reason: "boom"}}, 500
    end
  end

  describe "handle_circuit_open/1" do
    test "fails run with circuit-breaker message", ctx do
      %{state: state, run: run} = build_session(ctx)

      :ok = ChainRunner.handle_circuit_open(state)

      reloaded_run = FlowConversations.get_run!(run.id)
      assert reloaded_run.status == "failed"
      assert reloaded_run.error_message =~ "Circuit breaker"
    end
  end
end
