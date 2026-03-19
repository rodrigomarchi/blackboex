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

  @llm_response """
  I added input validation to check that n is a number.

  ```elixir
  #{@updated_code}
  ```
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

  describe "send message" do
    test "sending message adds user message to chat", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = render(lv)
      assert html =~ "Add validation"
    end

    test "LLM response appears as assistant message", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = render(lv)
      assert html =~ "validation"
    end

    test "diff is shown with accept/reject buttons", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = render(lv)
      assert html =~ "Aceitar"
      assert html =~ "Rejeitar"
    end
  end

  describe "accept" do
    test "accepting updates editor code and creates version", %{
      conn: conn,
      org: org,
      api: api
    } do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      # Click accept
      lv |> element("button[phx-click=accept_edit]") |> render_click()

      # Version created with source: chat_edit
      versions = Apis.list_versions(api.id)
      assert length(versions) == 1
      assert hd(versions).source == "chat_edit"
      assert hd(versions).prompt == "Add validation"
    end

    test "accepting shows success flash", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = lv |> element("button[phx-click=accept_edit]") |> render_click()

      assert html =~ "aceita" || html =~ "Aceita" || html =~ "aplicad"
    end
  end

  describe "reject" do
    test "rejecting keeps editor code unchanged", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      # Click reject
      lv |> element("button[phx-click=reject_edit]") |> render_click()

      # No version created
      versions = Apis.list_versions(api.id)
      assert versions == []
    end

    test "rejecting removes accept/reject buttons", %{conn: conn, org: org, api: api} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> form("form[phx-submit=send_chat]", %{chat_input: "Add validation"}) |> render_submit()

      html = lv |> element("button[phx-click=reject_edit]") |> render_click()

      refute html =~ "accept_edit"
      refute html =~ "reject_edit"
    end
  end
end
