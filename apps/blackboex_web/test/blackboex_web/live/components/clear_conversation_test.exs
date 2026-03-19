defmodule BlackboexWeb.Components.ClearConversationTest do
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
        name: "Clear Test API",
        slug: "clear-test",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{org: org, api: api}
  end

  describe "clear conversation" do
    test "clear button is present in chat panel", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render(lv)
      assert html =~ "clear_conversation"
    end

    test "clearing resets messages to empty", %{conn: conn, org: org, api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv} = Conversations.append_message(conv, "user", "Hello")
      {:ok, _conv} = Conversations.append_message(conv, "assistant", "Hi there")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Verify messages exist
      html = render(lv)
      assert html =~ "Hello"

      # Clear
      lv |> element("button[phx-click=clear_conversation]") |> render_click()

      html = render(lv)
      refute html =~ "Hello"
      refute html =~ "Hi there"
      assert html =~ "Descreva"
    end

    test "code remains intact after clearing", %{conn: conn, org: org, api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, _conv} = Conversations.append_message(conv, "user", "Hello")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element("button[phx-click=clear_conversation]") |> render_click()

      # Code should still be present
      html = render(lv)
      assert html =~ "Code Editor"
    end

    test "clears messages in database", %{conn: conn, org: org, api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, _conv} = Conversations.append_message(conv, "user", "Hello")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element("button[phx-click=clear_conversation]") |> render_click()

      # Check database
      {:ok, reloaded} = Conversations.get_or_create_conversation(api.id)
      assert reloaded.messages == []
    end
  end
end
