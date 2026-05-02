defmodule BlackboexWeb.PageLive.EditChatTest do
  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :liveview

  # The LiveView logs warnings on simulated :run_failed broadcasts; capture so
  # the suite output is clean.
  @moduletag :capture_log

  alias Blackboex.PageAgent.KickoffWorker
  alias Blackboex.PageConversations
  alias Blackboex.Pages

  setup :register_and_log_in_user

  setup %{user: user} do
    org = org_fixture(%{user: user})
    project = project_fixture(%{user: user, org: org})
    page = page_fixture(%{user: user, org: org, project: project, title: "My Page"})
    %{org: org, project: project, page: page}
  end

  defp edit_path(org, project, page) do
    ~p"/orgs/#{org.slug}/projects/#{project.slug}/pages/#{page.slug}/edit"
  end

  defp open_chat(view) do
    view
    |> element(~s(button[phx-click="toggle_chat"]))
    |> render_click()
  end

  describe "mount" do
    test "initializes chat assigns with empty defaults", ctx do
      {:ok, view, html} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      assert html =~ "Page Assistant"
      # chat panel renders (open by default)
      assert has_element?(view, "#page-chat-timeline")
    end

    test "hydrates chat history from existing active conversation", ctx do
      conv = page_conversation_fixture(%{page: ctx.page})
      run = page_run_fixture(%{conversation: conv, user: ctx.user})

      {:ok, _} =
        PageConversations.append_event(run, %{
          event_type: "user_message",
          content: "pedido antigo"
        })

      {:ok, _view, html} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      assert html =~ "pedido antigo"
    end
  end

  describe "toggle_chat" do
    test "collapses and re-opens the chat sidebar", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))

      open_chat(view)
      refute has_element?(view, "#page-chat-timeline")

      open_chat(view)
      assert has_element?(view, "#page-chat-timeline")
    end
  end

  describe "send_chat" do
    test "empty message is a no-op — nothing enqueued", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))

      view
      |> form(~s(form[phx-submit="send_chat"]), %{message: "   "})
      |> render_submit()

      refute_enqueued(worker: KickoffWorker)
    end

    test "valid message enqueues Oban job and appends the user message", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))

      html =
        view
        |> form(~s(form[phx-submit="send_chat"]), %{message: "escreva intro"})
        |> render_submit()

      assert html =~ "escreva intro"
      assert html =~ "Agente pensando"

      assert_enqueued(
        worker: KickoffWorker,
        args: %{"page_id" => ctx.page.id, "trigger_message" => "escreva intro"}
      )
    end

    test "chat_input_change updates input assign", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))

      html =
        view
        |> form(~s(form[phx-submit="send_chat"]), %{message: "parcial"})
        |> render_change()

      assert html =~ ~s(value="parcial")
    end
  end

  describe "PubSub flow" do
    test ":run_started triggers thinking state and subscribes to run topic", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})

      assert render(view) =~ "Agente pensando"
    end

    test ":content_delta accumulates into the streaming block", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})
      send(view.pid, {:content_delta, %{delta: "# Título AI", run_id: run_id}})

      html = render(view)
      assert html =~ "Título AI"
    end

    test ":run_completed reloads page, appends assistant message, updates content", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})

      # Persist the edit before broadcasting (matches the ChainRunner order).
      {:ok, _} =
        Pages.record_ai_edit(ctx.page, "# AI-generated body", %{
          user: ctx.user,
          organization: ctx.org
        })

      send(
        view.pid,
        {:run_completed,
         %{
           content: "# AI-generated body",
           summary: "wrote body",
           run_id: run_id,
           run: nil
         }}
      )

      html = render(view)
      assert html =~ "wrote body"
      refute html =~ "Agente pensando"

      reloaded = Pages.get_page(ctx.project.id, ctx.page.id)
      assert reloaded.content == "# AI-generated body"
    end

    test ":run_failed appends a generic system message and flashes", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})
      send(view.pid, {:run_failed, %{reason: "LLM falhou", run_id: run_id}})

      html = render(view)
      assert html =~ "Agente falhou"
      # Generic message — never echo internal reason to the user.
      refute html =~ "LLM falhou"
    end

    test ":chat_slow_warning adds a warning message when still loading", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})

      send(view.pid, :chat_slow_warning)

      assert render(view) =~ "demorando"
    end

    test "deltas from a different run_id are ignored", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      send(view.pid, {:run_started, %{run_id: "a", run_type: "edit", page_id: ctx.page.id}})
      send(view.pid, {:content_delta, %{delta: "NOISE", run_id: "other"}})

      refute render(view) =~ "NOISE"
    end
  end

  describe "new_chat" do
    test "archives active conversation and clears chat_messages", ctx do
      conv = page_conversation_fixture(%{page: ctx.page})
      run = page_run_fixture(%{conversation: conv, user: ctx.user})

      {:ok, _} =
        PageConversations.append_event(run, %{
          event_type: "user_message",
          content: "velho pedido"
        })

      {:ok, view, html} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      assert html =~ "velho pedido"

      html =
        view
        |> element(~s(button[phx-click="new_chat"]))
        |> render_click()

      refute html =~ "velho pedido"

      old = PageConversations.get_conversation(conv.id)
      assert old.status == "archived"

      active = PageConversations.get_active_conversation(ctx.page.id)
      assert active && active.id != conv.id
    end

    test "is blocked while chat is loading", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()
      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})

      html = render(view)
      # New conversation button is disabled during loading
      assert html =~ "disabled"
      assert html =~ ~s(phx-click="new_chat")
    end
  end

  describe "error UX" do
    test "generic flash message — no inspect/internal data leaked", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})
      send(view.pid, {:run_failed, %{reason: "boom %Internal{...}", run_id: run_id}})

      html = render(view)
      assert html =~ "Agente falhou"
      # Flash uses the generic message, not the raw reason.
      refute html =~ "%Internal{"
    end

    test "slow_warning is suppressed after run_completed arrived first", ctx do
      {:ok, view, _} = live(ctx.conn, edit_path(ctx.org, ctx.project, ctx.page))
      run_id = Ecto.UUID.generate()

      send(view.pid, {:run_started, %{run_id: run_id, run_type: "edit", page_id: ctx.page.id}})

      {:ok, _} =
        Pages.record_ai_edit(ctx.page, "x", %{user: ctx.user, organization: ctx.org})

      send(
        view.pid,
        {:run_completed, %{content: "x", summary: "ok", run_id: run_id, run: nil}}
      )

      send(view.pid, :chat_slow_warning)

      refute render(view) =~ "demorando"
    end
  end

  # Cross-org IDOR for the chat path is exercised at the agent layer
  # (Blackboex.PageAgentTest "cross-org scope returns :unauthorized") and at the
  # router level by SetOrganizationFromUrl. No additional LV-level test here.
end
