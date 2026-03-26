defmodule BlackboexWeb.ApiLive.ChatEditTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

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

    %{org: org, api: api}
  end

  describe "chat edit: accept" do
    test "send chat -> LLM responds with code -> accept -> version created",
         %{conn: conn, org: org, api: api} do
      proposed_code = """
      def handle(params) do
        a = Map.get(params, "a", 0)
        b = Map.get(params, "b", 0)
        %{result: a + b, sum: a + b}
      end
      """

      mock_stream_text_with_code(proposed_code, "Added sum field")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      # Send a chat message
      lv
      |> form("form[phx-submit=send_chat]", %{chat_input: "Add a sum field"})
      |> render_submit()

      # Wait for LLM Task to complete
      wait_for_chat(lv)

      html = render(lv)

      # Should show pending edit with accept/reject buttons
      assert html =~ "Accept"
      assert html =~ "Reject"

      # Accept the edit — code applied immediately, pipeline runs async
      html = lv |> element(~s(button[phx-click="accept_edit"])) |> render_click()
      assert html =~ "Change applied"
    end
  end

  describe "chat edit: reject" do
    test "send chat -> LLM responds with code -> reject -> no version created",
         %{conn: conn, org: org, api: api} do
      proposed_code = """
      def handle(params) do
        a = Map.get(params, "a", 0)
        b = Map.get(params, "b", 0)
        %{result: a * b}
      end
      """

      mock_stream_text_with_code(proposed_code, "Changed to multiplication")

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      lv
      |> form("form[phx-submit=send_chat]", %{chat_input: "Change to multiplication"})
      |> render_submit()

      wait_for_chat(lv)

      html = render(lv)
      assert html =~ "Accept"
      assert html =~ "Reject"

      # Reject the edit
      lv |> element(~s(button[phx-click="reject_edit"])) |> render_click()

      html = render(lv)

      # Accept/Reject buttons should be gone
      refute html =~ "Accept"

      # No version should have been created
      assert Apis.list_versions(api.id) == []
    end
  end

  defp mock_stream_text_with_code(code, explanation) do
    response = "#{explanation}\n\n```elixir\n#{String.trim(code)}\n```"
    stream = [{:token, response}]

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

  defp wait_for_chat(view) do
    Process.sleep(300)
    render(view)
  end
end
