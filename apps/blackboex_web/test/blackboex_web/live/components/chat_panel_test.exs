defmodule BlackboexWeb.Components.ChatPanelTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.Conversations

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Chat Test API",
        slug: "chat-test",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{org: org, api: api}
  end

  describe "ChatPanel rendering" do
    test "renders empty message list on mount", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      assert html =~ "Chat"
      assert html =~ "chat_input"
    end

    test "renders existing messages from database", %{conn: conn, org: org, api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv} = Conversations.append_message(conv, "user", "Add validation")
      {:ok, _conv} = Conversations.append_message(conv, "assistant", "Here is the updated code")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      assert html =~ "Add validation"
      assert html =~ "Here is the updated code"
    end

    test "renders user messages aligned right, assistant left", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv} = Conversations.append_message(conv, "user", "My message")
      {:ok, _conv} = Conversations.append_message(conv, "assistant", "Bot reply")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      # Both messages render
      assert html =~ "My message"
      assert html =~ "Bot reply"
      # User message right-aligned, assistant left-aligned
      assert html =~ "justify-end"
      assert html =~ "justify-start"
    end

    test "has input text and send button", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      assert html =~ "chat_input"
      assert html =~ "Enviar"
    end

    test "escapes HTML in message content (XSS prevention)", %{conn: conn, org: org, api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      xss_payload = "<script>alert('xss')</script>"
      {:ok, _conv} = Conversations.append_message(conv, "user", xss_payload)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      # Phoenix should escape the HTML — raw <script> must NOT appear
      refute html =~ "<script>alert"
      # But the escaped version should be present
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "3-panel layout" do
    test "renders Chat, Editor, and Info/Versions panels", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      assert html =~ "Chat"
      assert html =~ "Code Editor"
      assert html =~ "Info"
      assert html =~ "Versions"
    end
  end
end
