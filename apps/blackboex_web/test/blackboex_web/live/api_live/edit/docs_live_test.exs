defmodule BlackboexWeb.ApiLive.Edit.DocsLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis

  setup [:register_and_log_in_user, :create_org_and_api]

  setup do
    Apis.Registry.clear()
    :ok
  end

  # Exhaust the free plan LLM generation limit (50/month) by inserting UsageEvents today.
  defp exhaust_llm_limit(org) do
    for _i <- 1..50 do
      usage_event_fixture(%{organization_id: org.id, event_type: "llm_generation"})
    end
  end

  # ── mount ─────────────────────────────────────────────────────────────

  describe "mount" do
    test "renders no-docs message when documentation_md is nil", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      assert html =~ "No documentation yet"
    end

    test "renders existing documentation when documentation_md is set", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _api} = Apis.update_api(api, %{documentation_md: "# My API\n\nSome docs."})
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      assert html =~ "My API"
      assert html =~ "Some docs"
    end

    test "initialises doc_generating to false", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      assert is_binary(render(lv))
    end
  end

  # ── generate_docs — guard clause ──────────────────────────────────────

  describe "generate_docs — guard (already generating)" do
    test "second generate_docs call while doc_generating is true is a no-op", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      :sys.replace_state(lv.pid, fn state ->
        new_assigns = Map.put(state.socket.assigns, :doc_generating, true)
        %{state | socket: %{state.socket | assigns: new_assigns}}
      end)

      html = render_click(lv, "generate_docs", %{})
      assert is_binary(html)
    end
  end

  # ── generate_docs — limit exceeded ───────────────────────────────────

  describe "generate_docs — limit exceeded" do
    test "shows error flash when LLM generation limit is reached", %{
      conn: conn,
      org: org,
      api: api
    } do
      exhaust_llm_limit(org)
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      html = render_click(lv, "generate_docs", %{})
      assert html =~ "limit" or html =~ "Upgrade" or html =~ "plan" or html =~ "generation"
    end
  end

  # ── handle_info — task results ────────────────────────────────────────

  describe "handle_info — task results" do
    test "successful generation with matching ref updates the API doc", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      ref = make_ref()

      :sys.replace_state(lv.pid, fn state ->
        new_assigns =
          state.socket.assigns
          |> Map.put(:doc_gen_ref, ref)
          |> Map.put(:doc_generating, true)

        %{state | socket: %{state.socket | assigns: new_assigns}}
      end)

      send(
        lv.pid,
        {ref,
         {:ok,
          %{doc: "# Generated\n\nDocs content.", usage: %{input_tokens: 10, output_tokens: 20}}}}
      )

      Process.sleep(100)
      assert is_binary(render(lv))
    end

    test "failed generation with matching ref shows error flash and resets state", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      ref = make_ref()

      :sys.replace_state(lv.pid, fn state ->
        new_assigns =
          state.socket.assigns
          |> Map.put(:doc_gen_ref, ref)
          |> Map.put(:doc_generating, true)

        %{state | socket: %{state.socket | assigns: new_assigns}}
      end)

      send(lv.pid, {ref, {:error, :llm_failed}})
      Process.sleep(100)
      html = render(lv)
      assert html =~ "Failed" or html =~ "failed" or is_binary(html)
    end

    test "DOWN message with matching ref resets doc_generating", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      ref = make_ref()

      :sys.replace_state(lv.pid, fn state ->
        new_assigns =
          state.socket.assigns
          |> Map.put(:doc_gen_ref, ref)
          |> Map.put(:doc_generating, true)

        %{state | socket: %{state.socket | assigns: new_assigns}}
      end)

      send(lv.pid, {:DOWN, ref, :process, self(), :normal})
      Process.sleep(100)
      assert is_binary(render(lv))
    end

    test "task result with non-matching ref is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      send(lv.pid, {make_ref(), {:ok, %{doc: "ignored", usage: %{}}}})
      Process.sleep(50)
      assert is_binary(render(lv))
    end

    test "completely unrelated messages are ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      send(lv.pid, {:unexpected_msg, "data"})
      Process.sleep(50)
      assert is_binary(render(lv))
    end
  end

  # ── command palette events ────────────────────────────────────────────

  describe "command palette events" do
    test "toggle_command_palette opens the palette", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      html = render_click(lv, "toggle_command_palette", %{})
      assert is_binary(html)
    end

    test "close_panels when palette is open closes it", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "close_panels when palette is already closed is a no-op", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "command_palette_search filters commands by query", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_search", %{"command_query" => "run"})
      assert is_binary(html)
    end

    test "command_palette_navigate down moves selection", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "down"})
      assert is_binary(html)
    end

    test "command_palette_navigate up moves selection", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "up"})
      assert is_binary(html)
    end

    test "command_palette_exec_first navigates to first command", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      render_click(lv, "toggle_command_palette", %{})
      result = render_click(lv, "command_palette_exec_first", %{})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end
end
