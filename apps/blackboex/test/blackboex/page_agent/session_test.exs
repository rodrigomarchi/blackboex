defmodule Blackboex.PageAgent.SessionTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration

  alias Blackboex.PageAgent.Session
  alias Blackboex.PageConversations

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})
    conv = page_conversation_fixture(%{page: page})

    run =
      page_run_fixture(%{
        conversation: conv,
        user: user,
        run_type: "edit",
        trigger_message: "do it"
      })

    Phoenix.PubSub.subscribe(Blackboex.PubSub, "page_agent:run:#{run.id}")

    %{
      opts: %{
        run_id: run.id,
        page_id: page.id,
        conversation_id: conv.id,
        organization_id: org.id,
        user_id: user.id,
        run_type: :edit,
        trigger_message: "do it",
        content_before: ""
      },
      run: run,
      page: page
    }
  end

  describe "init/1" do
    test "builds Session struct from opts and schedules :start_chain", %{opts: opts} do
      {:ok, state} = Session.init(opts)

      assert %Session{} = state
      assert state.run_id == opts.run_id
      assert state.page_id == opts.page_id
      assert state.run_type == :edit
      assert state.content_before == ""
      assert_received :start_chain
    end

    test "defaults nil content_before to empty string" do
      opts = %{
        run_id: Ecto.UUID.generate(),
        page_id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        organization_id: Ecto.UUID.generate(),
        user_id: 1,
        run_type: :generate,
        trigger_message: "x",
        content_before: nil
      }

      {:ok, state} = Session.init(opts)
      assert state.content_before == ""
    end
  end

  describe "child_spec/1" do
    test "builds a temporary worker spec keyed by run_id", %{opts: opts} do
      spec = Session.child_spec(opts)
      assert spec.id == {Session, opts.run_id}
      assert spec.restart == :temporary
    end
  end

  describe "start/1 lifecycle" do
    test "boots Session under SessionSupervisor and persists run as failed when LLM not stubbed",
         %{opts: opts, run: run} do
      # The default test config has no real LLM client behind the mock — the
      # session will spawn the chain, ContentPipeline will fail/timeout fast
      # via the unstubbed Mox call, and the run gets persisted as failed.
      Mox.stub(Blackboex.LLM.ClientMock, :stream_text, fn _, _ -> {:error, :no_stub} end)
      Mox.stub(Blackboex.LLM.ClientMock, :generate_text, fn _, _ -> {:error, :no_stub} end)
      Mox.set_mox_global()

      assert {:ok, pid} = Session.start(opts)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000

      reloaded = PageConversations.get_run!(run.id)
      assert reloaded.status == "failed"
    end
  end
end
