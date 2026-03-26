defmodule BlackboexWeb.Components.ChatFlowTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  @original_code """
  def handle(params) do
    %{result: params["n"] * 2}
  end
  """

  @updated_code """
  def handle(params) do
    n = Map.get(params, "n", 0)
    if is_number(n), do: %{result: n * 2}, else: %{error: "n must be a number"}
  end
  """

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
        source_code: String.trim(@original_code)
      })

    %{org: org, api: api}
  end

  defp open_chat(lv) do
    lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()
  end

  defp mock_chat_pipeline do
    response = "I added input validation.\n\n```elixir\n#{@updated_code}\n```"
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

  defp send_chat_and_wait(lv) do
    lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()
    Process.sleep(300)
    render(lv)
  end

  describe "send message" do
    test "sending message adds user message to chat", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = render(lv)
      assert html =~ "Add validation"
    end

    test "LLM response appears as assistant message", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = send_chat_and_wait(lv)
      assert html =~ "validation"
    end

    test "diff is shown with accept/reject buttons", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = send_chat_and_wait(lv)
      assert html =~ "Accept"
      assert html =~ "Reject"
    end
  end

  describe "accept" do
    test "accepting updates editor code and creates version", %{
      conn: conn,
      org: org,
      api: api
    } do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      send_chat_and_wait(lv)

      # Click accept — code applied, pipeline starts async
      lv |> element("button[phx-click=accept_edit]") |> render_click()

      # Wait for pipeline to complete and create version
      Process.sleep(2000)
      render(lv)

      versions = Apis.list_versions(api.id)
      assert length(versions) >= 1
    end

    test "accepting shows success flash", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      send_chat_and_wait(lv)

      html = lv |> element("button[phx-click=accept_edit]") |> render_click()

      # Flash confirms acceptance
      assert html =~ "Change applied"
    end
  end

  describe "reject" do
    test "rejecting keeps editor code unchanged", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      send_chat_and_wait(lv)

      # Click reject
      lv |> element("button[phx-click=reject_edit]") |> render_click()

      # No version created
      versions = Apis.list_versions(api.id)
      assert versions == []
    end

    test "rejecting removes accept/reject buttons", %{conn: conn, org: org, api: api} do
      mock_chat_pipeline()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      send_chat_and_wait(lv)

      html = lv |> element("button[phx-click=reject_edit]") |> render_click()

      refute html =~ "accept_edit"
      refute html =~ "reject_edit"
    end
  end
end
