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

  # Use toolbar-specific selectors to avoid matching panel close buttons
  defp toolbar_chat(lv), do: lv |> element(~s|button[title="Chat (⌘L)"]|)
  defp toolbar_test(lv), do: lv |> element(~s|button[title="Testing (⌘J)"]|)
  defp toolbar_config(lv), do: lv |> element(~s|button[title="Configurações (⌘I)"]|)

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

  describe "panel toggling" do
    test "chat panel opens and closes", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      refute html =~ "Descreva as mudanças"

      html = toolbar_chat(lv) |> render_click()
      assert html =~ "Descreva as mudanças"

      html = toolbar_chat(lv) |> render_click()
      refute html =~ "Descreva as mudanças"
    end

    test "config panel opens and shows all sections", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = toolbar_config(lv) |> render_click()

      assert html =~ "Informações"
      assert html =~ "API Keys"
      assert html =~ "Publicação"
      assert html =~ "calculator"
      assert html =~ "computation"
    end

    test "bottom panel opens on test tab by default", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = toolbar_test(lv) |> render_click()

      assert html =~ "Enviar"
      assert html =~ "History"
    end

    test "switching right panel from chat to config", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = toolbar_chat(lv) |> render_click()
      assert html =~ "Descreva as mudanças"
      refute html =~ "Informações"

      html = toolbar_config(lv) |> render_click()
      refute html =~ "Descreva as mudanças"
      assert html =~ "Informações"
    end

    test "escape closes panels in order: right then bottom", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      toolbar_chat(lv) |> render_click()
      toolbar_test(lv) |> render_click()

      # First escape closes right panel (chat)
      html = lv |> render_hook("close_panels", %{})
      refute html =~ "Descreva as mudanças"
      assert html =~ "Enviar"

      # Second escape closes bottom panel
      html = lv |> render_hook("close_panels", %{})
      refute html =~ "Enviar"
    end

    test "escape with no panels open is a no-op", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html_before = render(lv)
      lv |> render_hook("close_panels", %{})
      html_after = render(lv)

      assert html_before == html_after
    end

    test "bottom panel remembers tab after close/reopen", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      toolbar_test(lv) |> render_click()
      lv |> render_hook("switch_bottom_tab", %{"tab" => "versions"})
      toolbar_test(lv) |> render_click()

      html = toolbar_test(lv) |> render_click()
      assert html =~ "No versions yet"
    end

    test "switching between all bottom panel tabs", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      toolbar_test(lv) |> render_click()

      html = lv |> render_hook("switch_bottom_tab", %{"tab" => "validation"})
      assert html =~ "Validation"

      html = lv |> render_hook("switch_bottom_tab", %{"tab" => "versions"})
      assert html =~ "No versions yet"

      html = lv |> render_hook("switch_bottom_tab", %{"tab" => "test"})
      assert html =~ "Enviar"
    end

    test "panel close buttons work", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open and close chat via its X button
      toolbar_chat(lv) |> render_click()
      # The right panel has a close button with phx-click="toggle_chat" without title attr
      html = lv |> render_hook("toggle_chat", %{})
      refute html =~ "Descreva as mudanças"

      # Open and close bottom panel via its X button
      toolbar_test(lv) |> render_click()
      html = lv |> render_hook("toggle_bottom_panel", %{})
      refute html =~ "Enviar"
    end
  end

  describe "command palette" do
    test "opens and closes via toggle event", %{conn: conn, org: org, api: api} do
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      refute html =~ "Buscar comando"

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      assert html =~ "Buscar comando"

      html = lv |> render_hook("toggle_command_palette", %{})
      refute html =~ "Buscar comando"
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

      refute html =~ "Buscar comando"
      assert html =~ "Descreva as mudanças"
    end

    test "exec_first executes first match", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "chat"})

      html = lv |> render_hook("command_palette_exec_first", %{})

      refute html =~ "Buscar comando"
      assert html =~ "Descreva as mudanças"
    end

    test "exec_first with no matches keeps palette open", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      lv |> render_hook("command_palette_search", %{"command_query" => "zzzzz_nonexistent"})

      html = lv |> render_hook("command_palette_exec_first", %{})
      assert html =~ "Nenhum comando encontrado"
    end

    test "escape closes palette before other panels", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      toolbar_chat(lv) |> render_click()
      lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()

      html = lv |> render_hook("close_panels", %{})
      refute html =~ "Buscar comando"
      assert html =~ "Descreva as mudanças"
    end

    test "shows publish command only when compiled", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_command_palette"])) |> render_click()
      refute html =~ "Publish API"

      lv |> render_hook("toggle_command_palette", %{})

      # Compile directly and update status
      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Blackboex.CodeGen.Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})

      # Remount to pick up compiled status from DB
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

      html = toolbar_test(lv) |> render_click()

      assert html =~ "History"
      assert html =~ "curl"
      assert html =~ "python"
      assert html =~ "javascript"
      assert html =~ "No requests yet"
    end

    test "clear button hidden when no history", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = toolbar_test(lv) |> render_click()
      refute html =~ "Limpar"
    end
  end

  describe "compile state after save" do
    test "status badge updates after successful compile", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      assert html =~ "draft"

      # Compile directly and update status
      code = "def handle(_), do: %{ok: true}"
      {:ok, _module} = Blackboex.CodeGen.Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})

      # Remount to pick up compiled status from DB
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Status badge should now show "compiled" not "draft"
      assert html =~ "compiled"

      on_exit(fn ->
        module = Blackboex.CodeGen.Compiler.module_name_for(api)
        Blackboex.CodeGen.Compiler.unload(module)
      end)
    end
  end
end
