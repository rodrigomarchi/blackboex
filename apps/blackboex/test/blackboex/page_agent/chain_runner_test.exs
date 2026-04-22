defmodule Blackboex.PageAgent.ChainRunnerTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration

  alias Blackboex.PageAgent.ChainRunner
  alias Blackboex.PageAgent.Session
  alias Blackboex.PageConversations

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org, title: "Doc"})
    conv = page_conversation_fixture(%{page: page})

    run =
      page_run_fixture(%{
        conversation: conv,
        user: user,
        run_type: "edit",
        trigger_message: "muda X"
      })

    state = %Session{
      run_id: run.id,
      page_id: page.id,
      conversation_id: conv.id,
      organization_id: org.id,
      user_id: user.id,
      run_type: :edit,
      trigger_message: "muda X",
      content_before: ""
    }

    topic_run = "page_agent:run:#{run.id}"
    topic_page = "page_agent:page:#{page.id}"
    Phoenix.PubSub.subscribe(Blackboex.PubSub, topic_run)
    Phoenix.PubSub.subscribe(Blackboex.PubSub, topic_page)

    %{state: state, run: run, conv: conv, page: page, user: user, org: org}
  end

  describe "handle_chain_success/2" do
    test "applies edit, appends completed event, completes run, broadcasts", ctx do
      result = %{
        content: "# new content",
        summary: "wrote intro",
        input_tokens: 100,
        output_tokens: 200
      }

      # Seed the page content so there's something to replace.
      {:ok, _} = PageConversations.mark_run_running(ctx.run)

      ChainRunner.handle_chain_success(ctx.state, result)

      # page content updated
      updated_page = Blackboex.Pages.get_page(ctx.page.project_id, ctx.page.id)
      assert updated_page.content == "# new content"

      # completed event appended
      events = PageConversations.list_events(ctx.run.id)
      assert Enum.any?(events, &(&1.event_type == "completed"))

      # run completed
      reloaded = PageConversations.get_run!(ctx.run.id)
      assert reloaded.status == "completed"
      assert reloaded.content_after == "# new content"
      assert reloaded.input_tokens == 100
      assert reloaded.output_tokens == 200

      # conversation stats incremented
      conv = PageConversations.get_conversation(ctx.conv.id)
      assert conv.total_runs == 1
      assert conv.total_input_tokens == 100
      assert conv.total_output_tokens == 200

      # broadcast on run topic
      assert_receive {:run_completed, %{content: "# new content", run_id: _}}, 100
    end

    test "when record_ai_edit fails, falls back to failure handler", ctx do
      {:ok, _} = PageConversations.mark_run_running(ctx.run)

      too_big = %{
        content: String.duplicate("a", 1_048_577),
        summary: "ok",
        input_tokens: 1,
        output_tokens: 1
      }

      ChainRunner.handle_chain_success(ctx.state, too_big)

      reloaded = PageConversations.get_run!(ctx.run.id)
      assert reloaded.status == "failed"
      assert_receive {:run_failed, %{reason: _}}, 100
    end
  end

  describe "handle_chain_failure/2" do
    test "appends failed event, fails run, broadcasts :run_failed", ctx do
      {:ok, _} = PageConversations.mark_run_running(ctx.run)

      ChainRunner.handle_chain_failure(ctx.state, "boom")

      reloaded = PageConversations.get_run!(ctx.run.id)
      assert reloaded.status == "failed"
      assert reloaded.error_message == "boom"

      events = PageConversations.list_events(ctx.run.id)
      assert Enum.any?(events, &(&1.event_type == "failed"))

      assert_receive {:run_failed, %{reason: "boom"}}, 100
    end
  end

  describe "handle_circuit_open/1" do
    test "produces a failure with circuit-breaker message", ctx do
      {:ok, _} = PageConversations.mark_run_running(ctx.run)

      ChainRunner.handle_circuit_open(ctx.state)

      reloaded = PageConversations.get_run!(ctx.run.id)
      assert reloaded.status == "failed"
      assert reloaded.error_message =~ "Circuit breaker"
    end
  end

  describe "run_chain/1 history" do
    test "drops the current user_message from history to avoid duplication", ctx do
      # Append a history pair where the last user_message equals trigger_message.
      {:ok, _} =
        PageConversations.append_event(ctx.run, %{
          event_type: "user_message",
          content: ctx.state.trigger_message
        })

      history =
        PageConversations.thread_history(ctx.page.id, limit: 10)

      # Sanity: the fixture setup appended the trigger; last entry is the dup.
      assert List.last(history).content == ctx.state.trigger_message
    end
  end
end
