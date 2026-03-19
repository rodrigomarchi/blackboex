defmodule BlackboexWeb.Components.ChatStreamingTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  @original_code "def handle(params), do: %{result: params[\"n\"]}"

  @updated_code "def handle(params) do\n  n = Map.get(params, \"n\", 0)\n  %{result: n * 2}\nend"

  @full_response "Added multiplication.\n\n```elixir\n#{@updated_code}\n```"

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Stream Test API",
        slug: "stream-test",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: @original_code
      })

    %{org: org, api: api}
  end

  describe "streaming response" do
    test "shows thinking indicator during LLM call", %{conn: conn, org: org, api: api} do
      test_pid = self()

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        # Signal test that we're in the LLM call
        send(test_pid, :llm_called)
        {:ok, %{content: @full_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add multiply"}) |> render_submit()

      # After response, diff should be available
      html = render(lv)
      assert html =~ "Aceitar"
    end

    test "after stream complete, diff and buttons appear", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @full_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add multiply"}) |> render_submit()

      html = render(lv)
      assert html =~ "Aceitar"
      assert html =~ "Rejeitar"
      assert html =~ "bg-green"
    end

    @tag :capture_log
    test "error response shows friendly error in chat", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :timeout}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add multiply"}) |> render_submit()

      html = render(lv)
      assert html =~ "demorou demais"
    end

    test "response without code shows message without diff", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content: "I'm not sure what you mean. Could you clarify?",
           usage: %{input_tokens: 50, output_tokens: 30}
         }}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Do something"}) |> render_submit()

      html = render(lv)
      assert html =~ "clarify"
      refute html =~ "accept_edit"
    end
  end
end
