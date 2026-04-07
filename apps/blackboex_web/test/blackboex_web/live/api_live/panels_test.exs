defmodule BlackboexWeb.ApiLive.PanelsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations

  setup :register_and_log_in_user

  setup %{user: user} do
    Apis.Registry.clear()

    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Calculator",
        slug: "calculator",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    Apis.upsert_files(api, [
      %{path: "/src/handler.ex", content: "def handle(_), do: %{ok: true}", file_type: "source"}
    ])

    %{org: org, api: api}
  end

  describe "tab switching" do
    test "chat tab shows conversation panel", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      assert html =~ "Describe what you want"
    end

    test "publish tab shows publication section", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")
      assert html =~ "Publication"
      assert html =~ "Settings"
    end

    test "info tab shows API information", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")
      assert html =~ "calculator"
      assert html =~ "computation"
    end

    test "run tab shows request builder", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      assert html =~ "History"
    end

    test "switching between tabs", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/validation?org=#{org.id}")
      assert html =~ "Validation"

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")
      assert html =~ "No versions yet"

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      assert html =~ "History"

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      assert html =~ "Code"
    end

    test "switching from chat to publish shows publish content", %{conn: conn, org: org, api: api} do
      {:ok, _lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")
      assert html =~ "Publication"
    end
  end

  describe "command palette" do
    test "opens and closes via toggle event", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      refute html =~ "Search commands"

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      assert html =~ "Search commands"

      html = lv |> render_hook("toggle_command_palette", %{})
      refute html =~ "Search commands"
    end

    test "search filters commands", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("command_palette_search", %{"command_query" => "save"})
      assert html =~ "Save"
      refute html =~ "Toggle Chat"
    end

    test "executing a command closes palette and runs action", %{conn: conn, org: org, api: api} do
      conn_with_org = Plug.Conn.put_session(conn, :organization_id, org.id)
      {:ok, lv, _html} = live(conn_with_org, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      {:ok, _lv2, html} =
        lv
        |> render_hook("command_palette_exec", %{"event" => "toggle_chat"})
        |> follow_redirect(conn_with_org)

      refute html =~ "Search commands"
      assert html =~ "Describe what you want"
    end

    test "exec_first executes first match", %{conn: conn, org: org, api: api} do
      conn_with_org = Plug.Conn.put_session(conn, :organization_id, org.id)
      {:ok, lv, _html} = live(conn_with_org, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "chat"})

      {:ok, _lv2, html} =
        lv
        |> render_hook("command_palette_exec_first", %{})
        |> follow_redirect(conn_with_org)

      refute html =~ "Search commands"
      assert html =~ "Describe the changes"
    end

    test "exec_first with no matches keeps palette open", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "zzzzz_nonexistent"})

      html = lv |> render_hook("command_palette_exec_first", %{})
      assert html =~ "No commands found"
    end

    test "escape closes palette before other panels", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("close_panels", %{})
      refute html =~ "Search commands"
      assert html =~ "Describe what you want"
    end

    test "shows publish command only when compiled", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      refute html =~ "Publish API"

      lv |> render_hook("toggle_command_palette", %{})

      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      assert html =~ "Publish API"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  describe "test history" do
    test "shows history section with snippets", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      assert html =~ "History"
      assert html =~ "curl"
      assert html =~ "python"
      assert html =~ "javascript"
      assert html =~ "No requests yet"
    end

    test "clear button hidden when no history", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")
      refute html =~ "Limpar"
    end
  end

  describe "compile state after save" do
    test "status badge updates after successful compile", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")
      assert html =~ "draft"

      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      assert html =~ "compiled"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end
end
