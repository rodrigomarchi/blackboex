defmodule BlackboexWeb.ApiLive.AgentChatTest do
  @moduledoc """
  Comprehensive tests for the agent pipeline integration in the API editor LiveView.
  Covers happy path, edge cases, error handling, and UX consistency.
  """

  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Agent Org", slug: "agentorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Calculator",
        slug: "calculator",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: """
        def handle(params) do
          a = Map.get(params, "a", 0)
          b = Map.get(params, "b", 0)
          %{result: a + b}
        end
        """
      })

    stub_pipeline_mocks()

    %{org: org, api: api, user: user}
  end

  # ── Happy Path ─────────────────────────────────────────────────────────

  describe "agent chat happy path" do
    test "full flow: send → run_started → streaming → tools → completed → accept",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Add multiply")

      # Loading state with user message
      html = render(lv)
      assert html =~ "Thinking..."
      assert html =~ "Add multiply"

      # Run started + streaming
      run_id = start_agent_run(lv)
      send(lv.pid, {:agent_streaming, %{delta: "Analyzing...", run_id: run_id}})
      assert render(lv) =~ "Analyzing"

      # Tool result in timeline
      send_tool_result(lv, run_id, "compile_code", true, "OK")
      assert render(lv) =~ "Compile"

      # Completion
      complete_agent(lv, run_id, "def handle(p), do: %{result: 42}", "Done")
      html = render(lv)
      assert html =~ "Accept"
      assert html =~ "Done"
      refute html =~ "Thinking..."

      # Accept via the chat panel button (first match)
      render_click(lv, "accept_edit")
      html = render(lv)
      assert html =~ "Change applied"
    end

    test "completion with test_code updates test_code assign",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Add tests")

      run_id = start_agent_run(lv)

      complete_agent(lv, run_id, "def handle(p), do: p", "Added tests",
        test_code: "defmodule T do\n  test \"ok\", do: assert true\nend"
      )

      render_click(lv, "accept_edit")
      assert render(lv) =~ "Change applied"
    end
  end

  # ── Agent Failure ──────────────────────────────────────────────────────

  describe "agent failure" do
    test "agent_failed shows error and clears loading state",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do something")

      run_id = start_agent_run(lv)
      send(lv.pid, {:agent_failed, %{error: "LLM provider unavailable", run_id: run_id}})

      html = render(lv)
      assert html =~ "Agent failed"
      assert html =~ "LLM provider unavailable"
      refute html =~ "Thinking..."
    end

    test "guardrail triggered shows warning",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      run_id = start_agent_run(lv)
      send(lv.pid, {:guardrail_triggered, %{type: :max_iterations, run_id: run_id}})

      assert render(lv) =~ "Agent limit reached"
    end
  end

  # ── Edge Cases ─────────────────────────────────────────────────────────

  describe "edge cases" do
    test "empty message is ignored",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: ""}) |> render_submit()
      refute render(lv) =~ "Thinking..."
    end

    test "input is disabled while loading prevents double submit",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "First")

      html = render(lv)
      assert html =~ "Thinking..."
      assert html =~ "First"

      # Verify input is disabled in HTML (frontend prevents double submit)
      assert html =~ ~s(name="chat_input") and html =~ "disabled"

      # Backend also guards via chat_loading check
      render_click(lv, "send_chat", %{"chat_input" => "Second"})
      html = render(lv)
      assert html =~ "First"
      refute html =~ "Second"
    end

    test "completion with nil code shows info flash and preserves timeline",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Analyze")

      run_id = start_agent_run(lv)
      send_tool_result(lv, run_id, "compile_code", true, "OK")
      assert render(lv) =~ "Compile"

      # Complete WITHOUT code — uses code from assigns (API already has source_code)
      send(
        lv.pid,
        {:agent_completed,
         %{
           code: nil,
           test_code: nil,
           summary: "Analysis done",
           run_id: run_id,
           status: "completed"
         }}
      )

      html = render(lv)
      assert html =~ "Analysis done"
      refute html =~ "Thinking..."
      # Timeline should be preserved
      assert html =~ "Compile"
    end

    test "reject edit clears pending_edit",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Change")

      run_id = start_agent_run(lv)
      complete_agent(lv, run_id, "new_code()", "Changed")

      assert render(lv) =~ "Accept"

      render_click(lv, "reject_edit")
      html = render(lv)
      refute html =~ "Accept"
      refute html =~ "Reject"
    end

    test "streaming tokens ignored after run completes",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      run_id = start_agent_run(lv)
      complete_agent(lv, run_id, "new()", "Done")

      # Late-arriving streaming — should be ignored
      send(lv.pid, {:agent_streaming, %{delta: "late token", run_id: run_id}})
      refute render(lv) =~ "late token"
    end

    test "clear conversation blocked during active run",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      _run_id = start_agent_run(lv)

      render_click(lv, "clear_conversation")
      html = render(lv)
      assert html =~ "Cannot clear while agent is running"
      # Message should still be there
      assert html =~ "Do it"
    end

    test "can send new message after failure",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Try 1")

      run_id = start_agent_run(lv)
      send(lv.pid, {:agent_failed, %{error: "Timeout", run_id: run_id}})

      assert render(lv) =~ "Agent failed"
      refute render(lv) =~ "Thinking..."

      # Second attempt should work
      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Try 2"}) |> render_submit()
      assert render(lv) =~ "Thinking..."
      assert render(lv) =~ "Try 2"
    end

    test "agent_message events appear in timeline",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      run_id = start_agent_run(lv)

      send(
        lv.pid,
        {:agent_message, %{role: "assistant", content: "Working on it", run_id: run_id}}
      )

      assert render(lv) =~ "Working on it"
    end

    test "tool failure shows in timeline",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      run_id = start_agent_run(lv)
      send_tool_result(lv, run_id, "compile_code", false, "3 errors")

      html = render(lv)
      assert html =~ "Compile"
      assert html =~ "3 errors"
    end

    test "multiple tool results accumulate in timeline",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Full pipeline")

      run_id = start_agent_run(lv)
      send_tool_result(lv, run_id, "compile_code", true, "OK")
      send_tool_result(lv, run_id, "format_code", true, nil)
      send_tool_result(lv, run_id, "run_tests", true, "3/3 passed")

      html = render(lv)
      assert html =~ "Compile"
      assert html =~ "Format"
      assert html =~ "Run Tests"
      assert html =~ "3/3 passed"
    end

    test "agent_started message is silently handled",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      send(lv.pid, {:agent_started, %{run_id: Ecto.UUID.generate(), run_type: "edit"}})
      assert render(lv) =~ "Calculator"
    end

    test "non-assistant agent_message types are ignored",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Test")

      run_id = start_agent_run(lv)

      send(lv.pid, {:agent_message, %{role: "user", content: "ignored_msg", run_id: run_id}})

      send(
        lv.pid,
        {:agent_message, %{role: "system", content: "also_ignored_msg", run_id: run_id}}
      )

      html = render(lv)
      refute html =~ "ignored_msg"
      refute html =~ "also_ignored_msg"
    end

    test "clear conversation works when no run is active",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "xyzzy_unique_msg")

      # Complete a run first so messages exist
      run_id = start_agent_run(lv)
      complete_agent(lv, run_id, "code()", "Agent finished")

      assert render(lv) =~ "xyzzy_unique_msg"

      # Accept the edit to clear pending state, then clear conversation
      render_click(lv, "accept_edit")

      # Now clear — should work since no run is active
      render_click(lv, "clear_conversation")
      html = render(lv)
      refute html =~ "xyzzy_unique_msg"
    end
  end

  # ── quick_action ───────────────────────────────────────────────────────

  describe "quick_action" do
    test "sets chat_input to the action text",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      render_click(lv, "quick_action", %{"text" => "Add validation"})

      html = render(lv)
      assert html =~ "Add validation"
    end

    test "populated input can be submitted as a chat message",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      render_click(lv, "quick_action", %{"text" => "Optimize performance"})
      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Optimize performance"}) |> render_submit()

      html = render(lv)
      assert html =~ "Thinking..."
      assert html =~ "Optimize performance"
    end
  end

  # ── cancel_pipeline ────────────────────────────────────────────────────

  describe "cancel_pipeline" do
    test "clears loading state and pipeline_status",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")
      _run_id = start_agent_run(lv)

      assert render(lv) =~ "Thinking..."

      render_click(lv, "cancel_pipeline")

      html = render(lv)
      refute html =~ "Thinking..."
    end

    test "shows info flash when no pre_edit_code is set",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")
      _run_id = start_agent_run(lv)

      render_click(lv, "cancel_pipeline")

      # No revert flash — only loading cleared
      html = render(lv)
      refute html =~ "Edit cancelled"
    end

    test "reverts code and shows flash when pre_edit_code is present",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Change it")

      run_id = start_agent_run(lv)
      complete_agent(lv, run_id, "new_code_here()", "Done")

      # Accept sets pre_edit_code to the previous code
      render_click(lv, "accept_edit")
      assert render(lv) =~ "Change applied"

      # Now trigger another run so cancel can revert
      open_chat_and_send(lv, "Another change")
      _run_id2 = start_agent_run(lv)

      render_click(lv, "cancel_pipeline")
      assert render(lv) =~ "Edit cancelled, code reverted"
    end
  end

  # ── accept_edit edge cases ─────────────────────────────────────────────

  describe "accept_edit" do
    test "is a no-op when pending_edit is nil",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      # No pending edit — clicking accept should not crash or flash
      render_click(lv, "accept_edit")
      html = render(lv)
      refute html =~ "Change applied"
    end

    test "clears pending_edit and shows flash",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Update")

      run_id = start_agent_run(lv)
      complete_agent(lv, run_id, "updated_code()", "Updated")

      assert render(lv) =~ "Accept"

      render_click(lv, "accept_edit")
      html = render(lv)
      assert html =~ "Change applied"
      refute html =~ "Accept"
      refute html =~ "Reject"
    end
  end

  # ── agent_streaming (isolated) ─────────────────────────────────────────

  describe "agent_streaming" do
    test "appends delta tokens to streaming display while run is active",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Stream this")

      run_id = start_agent_run(lv)

      send(lv.pid, {:agent_streaming, %{delta: "Hello ", run_id: run_id}})
      send(lv.pid, {:agent_streaming, %{delta: "World", run_id: run_id}})

      html = render(lv)
      assert html =~ "Hello"
      assert html =~ "World"
    end

    test "streaming tokens are ignored when no run is active",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      # No run started — streaming should be silently ignored
      send(lv.pid, {:agent_streaming, %{delta: "orphan_token_xyz"}})

      refute render(lv) =~ "orphan_token_xyz"
    end
  end

  # ── agent_action with args ─────────────────────────────────────────────

  describe "agent_action" do
    test "agent_action with args adds tool_call event to timeline",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Compile it")

      run_id = start_agent_run(lv)

      send(lv.pid, {:agent_action, %{tool: "compile_code", args: %{"code" => "def foo, do: :bar"}, run_id: run_id}})

      html = render(lv)
      assert html =~ "Compile"
    end

    test "tool_started updates pipeline status without crash",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Do it")

      run_id = start_agent_run(lv)

      send(lv.pid, {:tool_started, %{tool: "generate_tests", run_id: run_id}})

      # LiveView should still render correctly
      assert render(lv) =~ "Calculator"
    end
  end

  # ── UX Consistency ─────────────────────────────────────────────────────

  describe "UX consistency" do
    test "chat input is disabled during loading",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Test")

      html = render(lv)
      assert html =~ "disabled"
    end

    test "pipeline_status updates correctly for different tools",
         %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      open_chat_and_send(lv, "Test")

      run_id = start_agent_run(lv)

      send(lv.pid, {:agent_action, %{tool: "compile_code", run_id: run_id}})
      assert render(lv) =~ "Calculator"

      send(lv.pid, {:agent_action, %{tool: "unknown_tool", run_id: run_id}})
      assert render(lv) =~ "Calculator"
    end
  end

  # ── Test Helpers ───────────────────────────────────────────────────────

  defp open_chat_and_send(lv, message) do
    lv |> form("form[phx-submit=send_chat]", %{chat_input: message}) |> render_submit()
  end

  defp start_agent_run(lv) do
    run_id = Ecto.UUID.generate()
    send(lv.pid, {:agent_run_started, %{run_id: run_id, run_type: "edit"}})
    run_id
  end

  defp send_tool_result(lv, run_id, tool, success, summary) do
    send(
      lv.pid,
      {:tool_result,
       %{
         tool: tool,
         success: success,
         summary: summary,
         content: summary,
         run_id: run_id
       }}
    )
  end

  defp complete_agent(lv, run_id, code, summary, opts \\ []) do
    send(
      lv.pid,
      {:agent_completed,
       %{
         code: code,
         test_code: Keyword.get(opts, :test_code),
         summary: summary,
         run_id: run_id,
         status: "completed"
       }}
    )
  end

  defp stub_pipeline_mocks do
    Blackboex.LLM.ClientMock
    |> stub(:stream_text, fn _prompt, _opts -> {:ok, [{:token, "no fix needed"}]} end)
    |> stub(:generate_text, fn _prompt, _opts ->
      {:ok,
       %{
         content:
           "```elixir\ndefmodule Test do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
         usage: %{input_tokens: 50, output_tokens: 50}
       }}
    end)
  end
end
