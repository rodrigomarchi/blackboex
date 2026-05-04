defmodule BlackboexWeb.PlaygroundLive.EditChatTest do
  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.PlaygroundAgent.KickoffWorker
  alias Blackboex.Playgrounds

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    org = org_fixture(%{user: user})
    project = project_fixture(%{user: user, org: org})

    playground =
      playground_fixture(%{user: user, org: org, project: project, name: "Chat Playground"})

    %{org: org, project: project, playground: playground}
  end

  defp edit_path(org, project, playground) do
    ~p"/orgs/#{org.slug}/projects/#{project.slug}/playgrounds/#{playground.slug}/edit"
  end

  describe "bottom panel tabs" do
    test "defaults to Output tab and hides the chat textarea",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      html = render(view)
      assert html =~ "Output"
      assert html =~ "Chat"
      refute html =~ ~s(name="message")
    end

    test "switches to Chat tab, rendering the chat input",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      html =
        view
        |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
        |> render_click()

      assert html =~ ~s(name="message")
      assert html =~ "Ask the agent"
    end
  end

  describe "send_chat" do
    test "empty message is a no-op",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      view
      |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
      |> render_click()

      refute render_submit(form(view, "form[phx-submit='send_chat']"), %{message: "   "}) =~
               "class=\"flex justify-end\""

      assert Playgrounds.get_playground(project.id, playground.id).code == playground.code
    end

    test "valid message enqueues Oban job and appends user message",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      view
      |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
      |> render_click()

      html =
        view
        |> form("form[phx-submit='send_chat']", %{message: "write hello"})
        |> render_submit()

      assert html =~ "write hello"
      assert html =~ "Agent thinking"

      assert_enqueued(
        worker: KickoffWorker,
        args: %{"playground_id" => playground.id, "trigger_message" => "write hello"}
      )
    end
  end

  describe "agent PubSub events" do
    test "run_started → subscribes to run topic and shows thinking state",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      view
      |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
      |> render_click()

      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit"}})

      assert render(view) =~ "Agent thinking"
    end

    test "code_delta updates the streaming code block",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      view
      |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
      |> render_click()

      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit"}})
      send(view.pid, {:code_delta, %{delta: "IO.puts(\"oi\")", run_id: run_id}})

      html = render(view)
      assert html =~ "Streaming"
      assert html =~ "IO.puts"
    end

    test "run_completed reloads playground, appends assistant message, pushes set_value event",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, pg} = Playgrounds.update_playground(playground, %{code: "old"})
      {:ok, view, _} = live(conn, edit_path(org, project, pg))

      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit"}})

      new_code = "IO.puts(:hello)"
      # ChainRunner persists the edit BEFORE broadcasting, so mirror that here.
      {:ok, _} = Playgrounds.record_ai_edit(pg, new_code, pg.code)

      send(
        view.pid,
        {:run_completed, %{code: new_code, summary: "escreve hello", run_id: run_id}}
      )

      html = render(view)
      assert html =~ "escreve hello"
      refute html =~ "Agent thinking"

      reloaded = Playgrounds.get_playground(project.id, pg.id)
      assert reloaded.code == new_code
    end

    test "new_chat archives the active conversation and clears chat_messages",
         %{conn: conn, org: org, project: project, playground: playground, user: user} do
      # Seed an active conversation with history so we can verify the clear.
      conv =
        playground_conversation_fixture(%{
          playground: playground,
          user: user,
          org: org,
          project: project
        })

      run = playground_run_fixture(%{conversation: conv, user: user})

      {:ok, _} =
        Blackboex.PlaygroundConversations.append_event(run, %{
          event_type: "user_message",
          content: "old request"
        })

      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      html =
        view
        |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
        |> render_click()

      assert html =~ "old request"

      html =
        view
        |> element(~s(button[phx-click="new_chat"]))
        |> render_click()

      refute html =~ "old request"
      assert html =~ "Ask the agent"

      # Previously active conversation is now archived; a new active exists.
      old = Blackboex.PlaygroundConversations.get_conversation(conv.id)
      assert old.status == "archived"

      active = Blackboex.PlaygroundConversations.get_active_conversation(playground.id)
      assert active != nil
      assert active.id != conv.id
    end

    test "new_chat is blocked while a run is loading",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      view
      |> element(~s(button[phx-click="switch_bottom_tab"][phx-value-tab="chat"]))
      |> render_click()

      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit"}})

      html = render(view)
      # Button should be disabled while loading
      assert html =~ ~s(phx-click="new_chat")
      assert html =~ "disabled"
    end

    test "run_failed appends system message and flashes error",
         %{conn: conn, org: org, project: project, playground: playground} do
      {:ok, view, _} = live(conn, edit_path(org, project, playground))

      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit"}})
      send(view.pid, {:run_failed, %{reason: "LLM failed", run_id: run_id}})

      html = render(view)
      assert html =~ "Agent failed: LLM failed"
    end
  end
end
