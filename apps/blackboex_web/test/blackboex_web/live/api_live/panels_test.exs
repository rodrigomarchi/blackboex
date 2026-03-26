defmodule BlackboexWeb.ApiLive.PanelsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{user: user} do
    Blackboex.Apis.Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Calculator",
        slug: "calculator",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}"
      })

    %{org: org, api: api}
  end

  defp stub_pipeline_mocks do
    Blackboex.LLM.ClientMock
    |> stub(:stream_text, fn _prompt, _opts ->
      {:ok, [{:token, "```elixir\ndef handle(_), do: %{ok: true}\n```"}]}
    end)
    |> stub(:generate_text, fn _prompt, _opts ->
      {:ok,
       %{
         content:
           "```elixir\ndefmodule Test do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
         usage: %{input_tokens: 50, output_tokens: 50}
       }}
    end)
  end

  defp wait_for_pipeline(lv) do
    Process.sleep(800)
    render(lv)
  end

  describe "tab switching" do
    test "chat sidebar opens and closes", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      refute html =~ "Describe the changes"

      html = render_click(lv, "toggle_chat", %{})
      assert html =~ "Describe the changes"

      html = render_click(lv, "toggle_chat", %{})
      refute html =~ "Describe the changes"
    end

    test "publish tab shows publication section", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "publish"})
      assert html =~ "Publication"
      assert html =~ "Settings"
    end

    test "info tab shows API information", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "info"})
      assert html =~ "calculator"
      assert html =~ "computation"
    end

    test "run tab shows request builder", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "run"})

      assert html =~ "History"
    end

    test "switching between tabs", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "validation"})
      assert html =~ "Validation"

      html = render_click(lv, "switch_tab", %{"tab" => "versions"})
      assert html =~ "No versions yet"

      html = render_click(lv, "switch_tab", %{"tab" => "run"})
      assert html =~ "History"

      html = render_click(lv, "switch_tab", %{"tab" => "code"})
      assert html =~ "Code"
    end

    test "chat sidebar stays open while switching tabs", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      render_click(lv, "toggle_chat", %{})
      html = render_click(lv, "switch_tab", %{"tab" => "publish"})

      assert html =~ "Describe the changes"
      assert html =~ "Publication"
    end
  end

  describe "command palette" do
    test "opens and closes via toggle event", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      refute html =~ "Search commands"

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      assert html =~ "Search commands"

      html = lv |> render_hook("toggle_command_palette", %{})
      refute html =~ "Search commands"
    end

    test "search filters commands", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("command_palette_search", %{"command_query" => "save"})
      assert html =~ "Save"
      refute html =~ "Toggle Chat"
    end

    test "executing a command closes palette and runs action", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("command_palette_exec", %{"event" => "toggle_chat"})

      refute html =~ "Search commands"
      assert html =~ "Describe the changes"
    end

    test "exec_first executes first match", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "chat"})

      html = lv |> render_hook("command_palette_exec_first", %{})

      refute html =~ "Search commands"
      assert html =~ "Describe the changes"
    end

    test "exec_first with no matches keeps palette open", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "zzzzz_nonexistent"})

      html = lv |> render_hook("command_palette_exec_first", %{})
      assert html =~ "No commands found"
    end

    test "escape closes palette before other panels", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      render_click(lv, "toggle_chat", %{})
      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("close_panels", %{})
      refute html =~ "Search commands"
      assert html =~ "Describe the changes"
    end

    test "shows publish command only when compiled", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      refute html =~ "Publish API"

      lv |> render_hook("toggle_command_palette", %{})

      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Blackboex.CodeGen.Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      assert html =~ "Publish API"

      on_exit(fn ->
        module = Blackboex.CodeGen.Compiler.module_name_for(api)
        Blackboex.CodeGen.Compiler.unload(module)
      end)
    end
  end

  describe "test history" do
    test "shows history section with snippets", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "run"})

      assert html =~ "History"
      assert html =~ "curl"
      assert html =~ "python"
      assert html =~ "javascript"
      assert html =~ "No requests yet"
    end

    test "clear button hidden when no history", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "run"})
      refute html =~ "Limpar"
    end
  end

  describe "compile state after save" do
    test "status badge updates after successful compile", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      assert html =~ "draft"

      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Blackboex.CodeGen.Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "compiled"

      on_exit(fn ->
        module = Blackboex.CodeGen.Compiler.module_name_for(api)
        Blackboex.CodeGen.Compiler.unload(module)
      end)
    end
  end
end
