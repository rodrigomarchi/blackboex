defmodule BlackboexWeb.Components.ChatErrorsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :unit

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
        name: "Error Test API",
        slug: "error-test",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{org: org, api: api}
  end

  defp send_chat_and_wait(lv, message \\ "Add validation") do
    lv |> form("form[phx-submit=send_chat]", %{chat_input: message}) |> render_submit()
    Process.sleep(300)
    render(lv)
  end

  describe "error handling" do
    @tag :capture_log
    test "LLM timeout shows friendly error message in chat", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:error, :timeout} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      html = send_chat_and_wait(lv)
      assert html =~ "Pipeline failed"
    end

    @tag :capture_log
    test "rate limit shows friendly error message in chat", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:error, :rate_limited} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      html = send_chat_and_wait(lv)
      assert html =~ "Pipeline failed"
    end

    @tag :capture_log
    test "network failure shows friendly error message", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:error, :econnrefused} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      html = send_chat_and_wait(lv)
      assert html =~ "Pipeline failed"
    end

    @tag :capture_log
    test "error does not leave chat in loading state", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts -> {:error, :timeout} end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      html = send_chat_and_wait(lv)
      refute html =~ "Pensando..."
    end

    test "empty message is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

      lv |> form("form[phx-submit=send_chat]", %{chat_input: ""}) |> render_submit()

      html = render(lv)
      assert html =~ "Descreva"
    end
  end
end
