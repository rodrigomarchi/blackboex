defmodule BlackboexWeb.Components.Editor.AgentChatPanelTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  import Phoenix.LiveViewTest

  alias BlackboexWeb.Components.Editor.Chat.Panel
  alias BlackboexWeb.Components.Editor.ChatPanel
  alias BlackboexWeb.Components.Editor.FlowChatPanel
  alias BlackboexWeb.Components.Editor.PageChatPanel
  alias BlackboexWeb.Components.Editor.PlaygroundChatPanel
  alias BlackboexWeb.Components.Editor.ProjectAgentChatPanel

  describe "canonical shell" do
    test "renders the shared shell, empty state, timeline hook, llm banner, and composer" do
      html =
        rendered_to_string(
          Panel.agent_chat_panel(%{
            title: "Shared Agent",
            icon: "hero-sparkles",
            timeline_id: "shared-agent-timeline",
            empty_description: "Ask the shared agent for a change.",
            input: "draft",
            input_name: "message",
            input_placeholder: "Describe the change...",
            loading: false,
            llm_configured?: false,
            configure_url: "/settings/llm"
          })
        )

      assert html =~ ~s(data-component="agent-chat-panel")
      assert html =~ "Shared Agent"
      assert html =~ ~s(id="shared-agent-timeline")
      assert html =~ ~s(phx-hook="ChatAutoScroll")
      assert html =~ "Ask the shared agent for a change."
      assert html =~ ~s(phx-submit="send_chat")
      assert html =~ ~s(phx-change="chat_input_change")
      assert html =~ ~s(name="message")
      assert html =~ "AI assist"
    end

    test "renders common message, system, thinking, and streaming timeline steps" do
      html =
        rendered_to_string(
          Panel.basic_timeline(%{
            messages: [
              %{role: "user", content: "write intro"},
              %{role: "assistant", content: "done"},
              %{role: "system", content: "Agent failed. Try again."}
            ],
            loading: true,
            current_stream: "def hello, do: :world",
            current_stream_mode: nil,
            thinking_label: "Agent thinking..."
          })
        )

      assert html =~ "write intro"
      assert html =~ "done"
      assert html =~ "Agent failed. Try again."
      assert html =~ "hello"
      refute html =~ "Agent thinking..."
    end
  end

  describe "chat adapters" do
    test "API, Page, Playground, Flow, and Project chats all use the canonical shell marker" do
      assert render_component(ChatPanel, api_assigns()) =~ ~s(data-component="agent-chat-panel")

      assert rendered_to_string(PageChatPanel.page_chat_panel(simple_assigns())) =~
               ~s(data-component="agent-chat-panel")

      assert rendered_to_string(PlaygroundChatPanel.playground_chat_panel(simple_assigns())) =~
               ~s(data-component="agent-chat-panel")

      assert rendered_to_string(
               FlowChatPanel.flow_chat_panel(Map.put(simple_assigns(), :current_stream_mode, nil))
             ) =~
               ~s(data-component="agent-chat-panel")

      assert rendered_to_string(ProjectAgentChatPanel.project_agent_chat_panel(project_assigns())) =~
               ~s(data-component="agent-chat-panel")
    end

    test "Project Agent user and assistant messages reuse the canonical timeline message style" do
      html = rendered_to_string(ProjectAgentChatPanel.project_agent_chat_panel(project_assigns()))

      assert html =~ "You"
      assert html =~ "Agent"
      refute html =~ "rounded-2xl"
    end
  end

  defp api_assigns do
    %{
      id: "chat-panel",
      events: [%{type: :message, role: "user", content: "build API", timestamp: nil}],
      pending_edit: nil,
      streaming_tokens: "",
      loading: false,
      run: nil,
      input: "",
      template_type: "computation"
    }
  end

  defp simple_assigns do
    %{
      messages: [%{role: "user", content: "write intro"}, %{role: "assistant", content: "done"}],
      input: "",
      loading: false,
      current_stream: nil,
      llm_configured?: true,
      configure_url: "/settings/llm"
    }
  end

  defp project_assigns do
    %{
      events: [
        %{id: "u1", kind: :user_message, content: "build a dashboard"},
        %{id: "a1", kind: :assistant_message, content: "I will draft a plan."}
      ],
      plan: nil,
      input: "",
      loading: false,
      llm_configured?: true,
      configure_url: "/settings/llm"
    }
  end
end
