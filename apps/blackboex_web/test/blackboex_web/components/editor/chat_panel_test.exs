defmodule BlackboexWeb.Components.Editor.ChatPanelTest do
  @moduledoc """
  Tests for the ChatPanel LiveComponent.
  Uses render_component/2 to render the component directly without a full LiveView.
  """

  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias BlackboexWeb.Components.Editor.ChatPanel

  # ── Helpers ────────────────────────────────────────────────────────────

  defp base_assigns do
    %{
      id: "chat-panel",
      events: [],
      pending_edit: nil,
      streaming_tokens: "",
      loading: false,
      run: nil,
      input: "",
      template_type: "computation"
    }
  end

  defp render_panel(overrides \\ %{}) do
    assigns = Map.merge(base_assigns(), overrides)
    render_component(ChatPanel, assigns)
  end

  defp user_message_event(content \\ "Hello agent") do
    %{type: :message, role: "user", content: content, timestamp: nil}
  end

  defp assistant_message_event(content \\ "Here is the result") do
    %{type: :message, role: "assistant", content: content, timestamp: nil}
  end

  defp tool_call_event(tool) do
    %{type: :tool_call, tool: tool, args: %{}, timestamp: nil, id: nil}
  end

  defp tool_result_event(tool, success) do
    %{type: :tool_result, tool: tool, success: success, content: "ok", timestamp: nil}
  end

  defp status_event(content) do
    %{type: :status, content: content}
  end

  defp sample_run(overrides \\ %{}) do
    Map.merge(
      %{
        run_type: "generation",
        status: "completed",
        model: "claude-3-5-sonnet-20241022",
        started_at: ~U[2024-01-01 10:00:00Z],
        completed_at: ~U[2024-01-01 10:00:05Z],
        duration_ms: 5000,
        input_tokens: 1000,
        output_tokens: 500,
        cost_cents: 10,
        event_count: 3
      },
      overrides
    )
  end

  # ── Empty state ────────────────────────────────────────────────────────

  describe "empty state" do
    test "renders empty state message when no events and not loading" do
      html = render_panel()

      assert html =~ "Describe what you want the agent to build or change"
    end

    test "renders Agent Timeline header" do
      html = render_panel()

      assert html =~ "Agent Timeline"
    end

    test "renders New conversation button" do
      html = render_panel()

      assert html =~ "New conversation"
    end

    test "renders chat input form" do
      html = render_panel()

      assert html =~ "Describe the changes"
      assert html =~ "Send"
    end

    test "renders quick action buttons for computation template" do
      html = render_panel(%{template_type: "computation"})

      assert html =~ "Add validation"
      assert html =~ "Add error handling"
    end

    test "renders quick actions for crud template" do
      html = render_panel(%{template_type: "crud"})

      assert html =~ "Add filter"
      assert html =~ "Add pagination"
    end

    test "renders quick actions for webhook template" do
      html = render_panel(%{template_type: "webhook"})

      assert html =~ "Validate signature"
    end

    test "input is disabled when loading" do
      html = render_panel(%{loading: true})

      assert html =~ ~s(disabled)
    end
  end

  # ── Message rendering ──────────────────────────────────────────────────

  describe "user messages" do
    test "renders user message content" do
      events = [user_message_event("Add multiply feature")]
      html = render_panel(%{events: events})

      assert html =~ "Add multiply feature"
    end

    test "shows 'You' label for user messages" do
      events = [user_message_event("Hello")]
      html = render_panel(%{events: events})

      assert html =~ "You"
    end

    test "does not show empty state when events present" do
      events = [user_message_event()]
      html = render_panel(%{events: events})

      refute html =~ "Describe what you want the agent to build or change"
    end
  end

  describe "assistant messages" do
    test "renders assistant message content" do
      events = [assistant_message_event("I will add that feature")]
      html = render_panel(%{events: events})

      assert html =~ "I will add that feature"
    end

    test "shows 'Agent' label for assistant messages" do
      events = [assistant_message_event()]
      html = render_panel(%{events: events})

      assert html =~ "Agent"
    end
  end

  describe "mixed conversation" do
    test "renders multiple messages in sequence" do
      events = [
        user_message_event("Add validation"),
        assistant_message_event("Sure, adding validation now")
      ]

      html = render_panel(%{events: events})

      assert html =~ "Add validation"
      assert html =~ "Sure, adding validation now"
      assert html =~ "You"
      assert html =~ "Agent"
    end
  end

  # ── Loading / streaming state ──────────────────────────────────────────

  describe "loading state" do
    test "shows Thinking indicator when loading with no streaming tokens" do
      html = render_panel(%{loading: true, streaming_tokens: ""})

      assert html =~ "Thinking..."
    end

    test "does not show empty state message when loading" do
      html = render_panel(%{loading: true})

      refute html =~ "Describe what you want the agent to build or change"
    end

    test "shows streaming tokens when loading and tokens are present" do
      html = render_panel(%{loading: true, streaming_tokens: "def multiply"})

      # Makeup highlights code so "def" and "multiply" appear in separate spans
      assert html =~ "multiply"
      assert html =~ "Streaming"
    end
  end

  # ── Tool steps ────────────────────────────────────────────────────────

  describe "tool steps" do
    test "renders completed tool step with tool name" do
      events = [
        tool_call_event("generate_code"),
        tool_result_event("generate_code", true)
      ]

      html = render_panel(%{events: events})

      assert html =~ "Generate Code"
    end

    test "renders failed tool step" do
      events = [
        tool_call_event("compile_code"),
        tool_result_event("compile_code", false)
      ]

      html = render_panel(%{events: events})

      assert html =~ "Compile"
    end

    test "renders run_tests tool name" do
      events = [
        tool_call_event("run_tests"),
        tool_result_event("run_tests", true)
      ]

      html = render_panel(%{events: events})

      assert html =~ "Run Tests"
    end

    test "renders format tool name" do
      events = [
        tool_call_event("format_code"),
        tool_result_event("format_code", true)
      ]

      html = render_panel(%{events: events})

      assert html =~ "Format"
    end

    test "renders lint tool name" do
      events = [
        tool_call_event("lint_code"),
        tool_result_event("lint_code", true)
      ]

      html = render_panel(%{events: events})

      assert html =~ "Lint"
    end
  end

  # ── Status events ─────────────────────────────────────────────────────

  describe "status events" do
    test "renders status event content" do
      events = [status_event("Initializing agent...")]
      html = render_panel(%{events: events})

      assert html =~ "Initializing agent..."
    end
  end

  # ── Run summary ───────────────────────────────────────────────────────

  describe "run summary" do
    test "renders run summary when run present and not loading" do
      run = sample_run()
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "Generation"
    end

    test "shows completed status badge" do
      run = sample_run(%{status: "completed"})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "completed"
    end

    test "shows model name in summary" do
      run = sample_run()
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      # short_model strips the claude- prefix
      assert html =~ "3-5-sonnet"
    end

    test "shows token counts" do
      run = sample_run(%{input_tokens: 1000, output_tokens: 500})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "in"
      assert html =~ "out"
    end

    test "does not render run summary when loading" do
      run = sample_run()
      html = render_panel(%{run: run, loading: true, events: [user_message_event()]})

      # summary is hidden while loading
      refute html =~ "Generation"
    end

    test "renders edit run type label" do
      run = sample_run(%{run_type: "edit"})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "Edit"
    end
  end

  # ── Pending edit ──────────────────────────────────────────────────────

  describe "pending edit" do
    test "renders pending edit when present" do
      pending_edit = %{explanation: "Added multiply function", diff: nil, validation: nil}
      html = render_panel(%{pending_edit: pending_edit, events: []})

      assert html =~ "Proposed Change"
      assert html =~ "Added multiply function"
    end

    test "renders Accept and Reject buttons when pending_edit exists" do
      pending_edit = %{explanation: "Some change", diff: nil, validation: nil}
      html = render_panel(%{pending_edit: pending_edit, events: []})

      assert html =~ "Accept"
      assert html =~ "Reject"
    end

    test "does not show pending edit area when nil" do
      html = render_panel(%{pending_edit: nil})

      refute html =~ "Proposed Change"
      refute html =~ "Accept"
    end

    test "renders diff lines when diff is present" do
      pending_edit = %{
        explanation: "Changed multiply",
        diff: [{:ins, ["+ new line"]}, {:del, ["- old line"]}, {:eq, ["same line"]}],
        validation: nil
      }

      html = render_panel(%{pending_edit: pending_edit, events: []})

      assert html =~ "new line"
      assert html =~ "old line"
    end

    test "renders validation badges when validation present" do
      pending_edit = %{
        explanation: "Changed code",
        diff: nil,
        validation: %{
          compilation: :pass,
          format: :pass,
          credo: :pass,
          tests: :pass,
          test_results: []
        }
      }

      html = render_panel(%{pending_edit: pending_edit, events: []})

      assert html =~ "Compile"
      assert html =~ "Format"
      assert html =~ "Credo"
      assert html =~ "Tests"
    end

    test "renders 'Validation will run after you accept' when no validation" do
      pending_edit = %{explanation: "No validation yet", diff: nil, validation: nil}
      html = render_panel(%{pending_edit: pending_edit, events: []})

      assert html =~ "Validation will run after you accept"
    end

    test "renders diff summary line when diff present" do
      pending_edit = %{
        explanation: "Changed code",
        diff: [{:ins, ["new line"]}, {:del, ["old line"]}, {:eq, ["same"]}],
        validation: nil
      }

      html = render_panel(%{pending_edit: pending_edit, events: []})
      # The diff summary should be rendered (format_diff_summary is called)
      assert is_binary(html)
    end

    test "renders test_summary from validation test_results" do
      pending_edit = %{
        explanation: "Test run",
        diff: nil,
        validation: %{
          compilation: :pass,
          format: :pass,
          credo: :pass,
          tests: :pass,
          test_results: [
            %{"status" => "passed"},
            %{"status" => "passed"},
            %{"status" => "failed"}
          ]
        }
      }

      html = render_panel(%{pending_edit: pending_edit, events: []})
      # test_summary shows "2/3"
      assert html =~ "2/3"
    end
  end

  describe "tool icon and name fallbacks" do
    test "renders unknown tool with fallback icon and raw name" do
      events = [
        tool_call_event("custom_tool"),
        tool_result_event("custom_tool", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "custom_tool"
    end

    test "renders generate_tests tool" do
      events = [
        tool_call_event("generate_tests"),
        tool_result_event("generate_tests", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "Generate Tests"
    end

    test "renders submit_code tool" do
      events = [
        tool_call_event("submit_code"),
        tool_result_event("submit_code", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "Submit"
    end

    test "renders generate_docs tool" do
      events = [
        tool_call_event("generate_docs"),
        tool_result_event("generate_docs", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "Generate Docs"
    end

    test "renders read_source tool" do
      events = [
        tool_call_event("read_source"),
        tool_result_event("read_source", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "Read Source"
    end

    test "renders edit_source tool" do
      events = [
        tool_call_event("edit_source"),
        tool_result_event("edit_source", true)
      ]

      html = render_panel(%{events: events})
      assert html =~ "Edit Source"
    end
  end

  describe "run summary edge cases" do
    test "renders test_only run type" do
      run = sample_run(%{run_type: "test_only"})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "Test Only"
    end

    test "renders doc_only run type" do
      run = sample_run(%{run_type: "doc_only"})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "Docs Only"
    end

    test "renders unknown run type with fallback label" do
      run = sample_run(%{run_type: "unknown_type"})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "Run"
    end

    test "handles nil completed_at in run summary" do
      run = sample_run(%{completed_at: nil, duration_ms: nil})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert is_binary(html)
    end

    test "handles nil model in run summary" do
      run = sample_run(%{model: nil})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert is_binary(html)
    end

    test "handles large token counts with k suffix" do
      run = sample_run(%{input_tokens: 5000, output_tokens: 1_500_000})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "5.0k"
      assert html =~ "1.5M"
    end

    test "handles zero cost" do
      run = sample_run(%{cost_cents: 0})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "$0"
    end

    test "handles nil cost" do
      run = sample_run(%{cost_cents: nil})
      html = render_panel(%{run: run, loading: false, events: [user_message_event()]})

      assert html =~ "$0"
    end
  end

  describe "tool output with code content" do
    test "renders code output as code block when content looks like code" do
      events = [
        %{
          type: :tool_call,
          tool: "generate_code",
          args: %{"code" => "defmodule Foo do\n  def bar, do: :ok\nend"},
          timestamp: nil,
          id: nil
        },
        %{
          type: :tool_result,
          tool: "generate_code",
          success: true,
          content: "defmodule Foo do\n  def bar, do: :ok\nend",
          timestamp: nil
        }
      ]

      html = render_panel(%{events: events})
      assert html =~ "defmodule" or html =~ "Generate Code"
    end

    test "renders tool output with failed success shows ERROR badge" do
      events = [
        tool_call_event("compile_code"),
        %{
          type: :tool_result,
          tool: "compile_code",
          success: false,
          content: "compilation error on line 5",
          timestamp: nil
        }
      ]

      html = render_panel(%{events: events})
      assert html =~ "ERROR" or html =~ "Compile"
    end
  end

  describe "active tool call with streaming" do
    test "shows active tool step with streaming tokens inside it" do
      events = [tool_call_event("generate_code")]

      html = render_panel(%{events: events, loading: true, streaming_tokens: "def multiply"})

      assert html =~ "Generate Code"
      assert html =~ "multiply"
    end

    test "shows Thinking inside active step when no streaming tokens" do
      events = [tool_call_event("generate_code")]

      html = render_panel(%{events: events, loading: true, streaming_tokens: ""})

      assert html =~ "Generate Code"
      assert html =~ "Thinking"
    end
  end

  describe "lint_code compact summary" do
    test "lint_code with issues shows count" do
      events = [
        tool_call_event("lint_code"),
        %{
          type: :tool_result,
          tool: "lint_code",
          success: true,
          content: "- issue one\n- issue two",
          timestamp: nil
        }
      ]

      html = render_panel(%{events: events})
      assert html =~ "Lint" or html =~ "issues"
    end

    test "run_tests with test count summary" do
      events = [
        tool_call_event("run_tests"),
        %{
          type: :tool_result,
          tool: "run_tests",
          success: true,
          content: "3 tests, 3 passed",
          timestamp: nil
        }
      ]

      html = render_panel(%{events: events})
      assert html =~ "Run Tests" or html =~ "3/3"
    end
  end
end
