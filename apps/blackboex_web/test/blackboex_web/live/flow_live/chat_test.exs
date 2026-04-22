defmodule BlackboexWeb.FlowLive.ChatTest do
  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.FlowConversations

  @moduletag :liveview

  setup :register_and_log_in_user

  defp do_setup_flow(user) do
    [org | _] = Blackboex.Organizations.list_user_organizations(user)

    {:ok, flow} =
      Blackboex.Flows.create_flow(%{
        name: "Chat Flow",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    %{org: org, flow: flow}
  end

  describe "mount" do
    test "chat is closed by default", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      refute has_element?(view, "#flow-chat-timeline")
    end

    test "'Agente' button is visible in header", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, _view, html} = live(conn, ~p"/flows/#{flow.id}/edit")

      assert html =~ "Agente"
    end
  end

  describe "toggle_chat" do
    test "clicking 'Agente' button opens the chat drawer", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      view |> element("button", "Agente") |> render_click()

      assert has_element?(view, "#flow-chat-timeline")
    end

    test "clicking 'Agente' twice closes the chat drawer", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      view |> element("button", "Agente") |> render_click()
      assert has_element?(view, "#flow-chat-timeline")

      view |> element("button", "Agente") |> render_click()
      refute has_element?(view, "#flow-chat-timeline")
    end
  end

  describe "send_chat" do
    test "empty message is a noop (no Oban job enqueued)", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")
      view |> element("button", "Agente") |> render_click()

      view
      |> form("form[phx-submit='send_chat']", %{"message" => "   "})
      |> render_submit()

      refute_enqueued(worker: Blackboex.FlowAgent.KickoffWorker)
    end

    test "valid message enqueues KickoffWorker and shows loading", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")
      view |> element("button", "Agente") |> render_click()

      html =
        view
        |> form("form[phx-submit='send_chat']", %{"message" => "crie um fluxo hello world"})
        |> render_submit()

      # user message shown in the timeline
      assert html =~ "crie um fluxo hello world"

      assert_enqueued(
        worker: Blackboex.FlowAgent.KickoffWorker,
        args: %{"flow_id" => flow.id, "trigger_message" => "crie um fluxo hello world"}
      )
    end
  end

  describe "handle_info broadcasts" do
    test "{:run_started} sets chat_loading and subscribes to run topic",
         %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      run_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:flow:#{flow.id}",
        {:run_started, %{run_id: run_id, run_type: "generate", flow_id: flow.id}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "Agente pensando"
    end

    test "{:definition_delta} appends to the stream view", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      run_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:flow:#{flow.id}",
        {:run_started, %{run_id: run_id, run_type: "generate", flow_id: flow.id}}
      )

      :timer.sleep(50)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:run:#{run_id}",
        {:definition_delta, %{delta: "{\"version\":\"1.0\"", run_id: run_id}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "version"
    end

    test "{:run_completed, kind: :explain} appends assistant message, NO canvas reload",
         %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")
      view |> element("button", "Agente") |> render_click()

      # Simulate a user having sent a message that's currently loading.
      view
      |> form("form[phx-submit='send_chat']", %{"message" => "me explica o fluxo"})
      |> render_submit()

      run_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:flow:#{flow.id}",
        {:run_started, %{run_id: run_id, run_type: "edit", flow_id: flow.id}}
      )

      :timer.sleep(50)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:run:#{run_id}",
        {:run_completed,
         %{kind: :explain, answer: "Esse fluxo valida o evento.", run_id: run_id}}
      )

      :timer.sleep(80)
      html = render(view)

      assert html =~ "Esse fluxo valida o evento"
      refute html =~ "Agente pensando"
    end

    test "{:run_completed} updates flow and pushes 'flow_chat:reload_definition'",
         %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      run_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:flow:#{flow.id}",
        {:run_started, %{run_id: run_id, run_type: "generate", flow_id: flow.id}}
      )

      :timer.sleep(50)

      new_definition = %{
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

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:run:#{run_id}",
        {:run_completed, %{run_id: run_id, definition: new_definition, summary: "criei o hello"}}
      )

      :timer.sleep(80)
      html = render(view)

      assert html =~ "criei o hello"
      refute html =~ "Agente pensando"
    end

    test "{:run_failed} shows system message", %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)
      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")

      run_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:flow:#{flow.id}",
        {:run_started, %{run_id: run_id, run_type: "generate", flow_id: flow.id}}
      )

      :timer.sleep(50)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "flow_agent:run:#{run_id}",
        {:run_failed, %{run_id: run_id, reason: "boom"}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "boom"
    end
  end

  describe "new_chat" do
    test "archives current conversation and clears messages",
         %{conn: conn, user: user} do
      %{flow: flow} = do_setup_flow(user)

      # Seed a conversation with one run + one user message event.
      {:ok, conv} =
        FlowConversations.get_or_create_active_conversation(
          flow.id,
          flow.organization_id,
          flow.project_id
        )

      {:ok, run} =
        FlowConversations.create_run(%{
          conversation_id: conv.id,
          flow_id: flow.id,
          organization_id: flow.organization_id,
          user_id: user.id,
          run_type: "edit",
          status: "completed",
          trigger_message: "oi"
        })

      {:ok, _} =
        FlowConversations.append_event(run, %{event_type: "user_message", content: "oi"})

      {:ok, view, _html} = live(conn, ~p"/flows/#{flow.id}/edit")
      view |> element("button", "Agente") |> render_click()
      assert render(view) =~ "oi"

      # Clicking "New conversation" archives the current thread.
      view |> element("button", "New conversation") |> render_click()

      # Old active conversation is archived
      refute FlowConversations.get_active_conversation(flow.id)
    end
  end
end
