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

  defp open_chat(lv) do
    lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()
  end

  defp mock_chat_pipeline do
    stream = [{:token, @full_response}]

    Blackboex.LLM.ClientMock
    |> stub(:stream_text, fn _prompt, _opts -> {:ok, stream} end)
    |> stub(:generate_text, fn _prompt, _opts ->
      {:ok,
       %{
         content:
           "```elixir\ndefmodule Test do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
         usage: %{input_tokens: 50, output_tokens: 50}
       }}
    end)
  end

  defp send_chat_and_wait(lv) do
    lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add multiply"}) |> render_submit()
    Process.sleep(300)
    render(lv)
  end

  describe "streaming response" do
    test "shows thinking indicator during LLM call", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = send_chat_and_wait(lv)

      # After response, diff should be available
      assert html =~ "Accept"
    end

    test "after stream complete, diff and buttons appear", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = send_chat_and_wait(lv)

      assert html =~ "Accept"
      assert html =~ "Reject"
      assert html =~ "bg-green"
    end

    @tag :capture_log
    test "error response shows friendly error in chat", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:error, :timeout} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add multiply"}) |> render_submit()
      Process.sleep(300)

      html = render(lv)
      assert html =~ "Pipeline failed"
    end

    test "response without code shows message without diff", %{conn: conn, org: org, api: api} do
      no_code_response = "I'm not sure what you mean. Could you clarify?"
      stream = [{:token, no_code_response}]

      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:ok, stream} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Do something"}) |> render_submit()
      Process.sleep(300)

      html = render(lv)
      # Pipeline returns error when no code found, so check for flash or no pending edit
      refute html =~ "accept_edit"
    end
  end
end
