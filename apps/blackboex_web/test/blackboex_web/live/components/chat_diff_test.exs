defmodule BlackboexWeb.Components.ChatDiffTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  # credo:disable-for-next-line Credo.Check.Readability.StringSigils
  @original_code "def handle(params) do\n  %{result: params[\"n\"] * 2}\nend"

  # credo:disable-for-next-line Credo.Check.Readability.StringSigils
  @updated_code "def handle(params) do\n  n = Map.get(params, \"n\", 0)\n  if is_number(n), do: %{result: n * 2}, else: %{error: \"invalid\"}\nend"

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Diff Test API",
        slug: "diff-test",
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

  defp mock_and_trigger_chat(lv) do
    response = "Updated.\n\n```elixir\n#{@updated_code}\n```"
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

    lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()
    Process.sleep(300)
    render(lv)
  end

  describe "ChatDiff rendering" do
    test "renders added lines in green", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = mock_and_trigger_chat(lv)

      # Added lines should have green styling
      assert html =~ "bg-green"
    end

    test "renders removed lines in red", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = mock_and_trigger_chat(lv)

      # Removed lines should have red styling
      assert html =~ "bg-red"
    end

    test "shows diff summary", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = mock_and_trigger_chat(lv)

      # Should show some indication of changes
      assert html =~ "added" || html =~ "removed" || html =~ "+"
    end
  end
end
