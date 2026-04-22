defmodule BlackboexWeb.Components.Editor.PageChatPanelTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  import Phoenix.LiveViewTest

  alias BlackboexWeb.Components.Editor.PageChatPanel

  defp render_panel(assigns) do
    assigns =
      Map.merge(
        %{
          messages: [],
          input: "",
          loading: false,
          current_stream: nil,
          open: true
        },
        assigns
      )

    rendered = PageChatPanel.page_chat_panel(assigns)
    rendered_to_string(rendered)
  end

  test "renders empty panel with header and input" do
    html = render_panel(%{})
    assert html =~ "Page Assistant"
    assert html =~ "Nova conversa"
    assert html =~ ~s(name="message")
  end

  test "renders user + assistant messages via render_message_step" do
    msgs = [
      %{role: "user", content: "escreva intro"},
      %{role: "assistant", content: "feito"}
    ]

    html = render_panel(%{messages: msgs})
    assert html =~ "escreva intro"
    assert html =~ "feito"
  end

  test "shows thinking indicator when loading and no tokens yet" do
    html = render_panel(%{loading: true})
    assert html =~ "Agente pensando"
  end

  test "renders streaming content block when tokens arriving" do
    html = render_panel(%{loading: true, current_stream: "# streaming\n"})
    assert html =~ "streaming"
  end

  test "wires send_chat, chat_input_change, new_chat events" do
    html = render_panel(%{})
    assert html =~ ~s(phx-submit="send_chat")
    assert html =~ ~s(phx-change="chat_input_change")
    assert html =~ ~s(phx-click="new_chat")
  end

  test "timeline container has id and ChatAutoScroll hook" do
    html = render_panel(%{messages: [%{role: "user", content: "x"}]})
    assert html =~ ~s(id="page-chat-timeline")
    assert html =~ ~s(phx-hook="ChatAutoScroll")
  end

  test "handles empty state without crashing" do
    html = render_panel(%{messages: [], current_stream: nil, loading: false})
    assert is_binary(html)
    assert html =~ "Page Assistant"
  end
end
