defmodule Blackboex.PlaygroundAgentIntegrationTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration

  import Mox

  alias Blackboex.PlaygroundAgent.ChainRunner
  alias Blackboex.PlaygroundAgent.Session
  alias Blackboex.PlaygroundConversations
  alias Blackboex.Playgrounds

  setup :verify_on_exit!

  defp build_session_state(playground, user, conversation, run, opts) do
    %Session{
      run_id: run.id,
      playground_id: playground.id,
      conversation_id: conversation.id,
      organization_id: playground.organization_id,
      user_id: user.id,
      run_type: opts[:run_type] || :edit,
      trigger_message: opts[:trigger_message] || "add a line",
      code_before: opts[:code_before] || playground.code || ""
    }
  end

  describe "end-to-end edit via ChainRunner" do
    setup [:create_user_and_org]

    test "mock LLM → code applied to playground + snapshot + event + broadcast",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      {:ok, pg} = Playgrounds.update_playground(pg, %{code: "x = 1\nx"})

      {:ok, conversation} =
        PlaygroundConversations.get_or_create_active_conversation(pg.id, org.id, pg.project_id)

      {:ok, run} =
        PlaygroundConversations.create_run(%{
          conversation_id: conversation.id,
          playground_id: pg.id,
          organization_id: org.id,
          user_id: user.id,
          run_type: "edit",
          trigger_message: "add y",
          code_before: pg.code
        })

      {:ok, _} =
        PlaygroundConversations.append_event(run, %{
          event_type: "user_message",
          content: "add y"
        })

      {:ok, _} = PlaygroundConversations.mark_run_running(run)
      run = PlaygroundConversations.get_run!(run.id)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "playground_agent:run:#{run.id}")

      canned = """
      Claro, vamos adicionar:
      ```elixir
      x = 1
      y = 2
      IO.puts(x + y)
      ```
      Resumo: soma x e y
      """

      expect(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        tokens = String.graphemes(canned)
        {:ok, Stream.map(tokens, & &1)}
      end)

      state = build_session_state(pg, user, conversation, run, trigger_message: "add y")

      assert {:ok, result} = ChainRunner.run_chain(state)
      assert result.code =~ "IO.puts(x + y)"
      assert result.summary == "soma x e y"

      :ok = ChainRunner.handle_chain_success(state, result)

      updated_pg = Playgrounds.get_playground(pg.project_id, pg.id)
      assert updated_pg.code =~ "IO.puts(x + y)"

      [snapshot] = Playgrounds.list_executions(pg.id)
      assert snapshot.status == "ai_snapshot"
      assert snapshot.code_snapshot == "x = 1\nx"

      completed = PlaygroundConversations.get_run!(run.id)
      assert completed.status == "completed"
      assert completed.code_after =~ "IO.puts(x + y)"
      assert completed.run_summary == "soma x e y"

      events = PlaygroundConversations.list_events(run.id)
      assert Enum.any?(events, &(&1.event_type == "user_message"))
      assert Enum.any?(events, &(&1.event_type == "completed"))

      assert_receive {:run_completed, %{code: code, summary: "soma x e y"}}, 500
      assert code =~ "IO.puts(x + y)"
    end

    test "LLM response without code block → failed run + :run_failed broadcast",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      {:ok, conversation} =
        PlaygroundConversations.get_or_create_active_conversation(pg.id, org.id, pg.project_id)

      {:ok, run} =
        PlaygroundConversations.create_run(%{
          conversation_id: conversation.id,
          playground_id: pg.id,
          organization_id: org.id,
          user_id: user.id,
          run_type: "generate",
          trigger_message: "faz algo",
          code_before: ""
        })

      {:ok, _} = PlaygroundConversations.mark_run_running(run)
      run = PlaygroundConversations.get_run!(run.id)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "playground_agent:run:#{run.id}")

      expect(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:ok, Stream.map(["só prosa sem fence"], & &1)}
      end)

      state = build_session_state(pg, user, conversation, run, run_type: :generate)

      assert {:error, reason} = ChainRunner.run_chain(state)
      assert reason =~ "bloco de código"

      :ok = ChainRunner.handle_chain_failure(state, reason)

      failed = PlaygroundConversations.get_run!(run.id)
      assert failed.status == "failed"
      assert failed.error_message =~ "bloco de código"

      assert_receive {:run_failed, %{reason: r}}, 500
      assert r =~ "bloco de código"
    end
  end

  describe "PlaygroundAgent.start/3" do
    setup [:create_user_and_org]

    test "enqueues Oban job with correct args for edit", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      {:ok, pg} = Playgrounds.update_playground(pg, %{code: "x = 1"})

      scope = %{user: user}

      assert {:ok, %Oban.Job{worker: "Blackboex.PlaygroundAgent.KickoffWorker", args: args}} =
               Blackboex.PlaygroundAgent.start(pg, scope, "  refactor  ")

      assert args["playground_id"] == pg.id
      assert args["run_type"] == "edit"
      assert args["code_before"] == "x = 1"
      assert args["trigger_message"] == "refactor"
    end

    test "picks :generate run type when playground code is empty",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      scope = %{user: user}

      assert {:ok, %Oban.Job{args: args}} =
               Blackboex.PlaygroundAgent.start(pg, scope, "escreva algo")

      assert args["run_type"] == "generate"
    end

    test "rejects empty messages without enqueuing", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      scope = %{user: user}

      assert {:error, :empty_message} =
               Blackboex.PlaygroundAgent.start(pg, scope, "   ")
    end
  end
end
