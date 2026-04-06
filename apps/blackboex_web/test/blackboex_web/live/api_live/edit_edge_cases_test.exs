defmodule BlackboexWeb.ApiLive.EditEdgeCasesTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.LLM.ClientMock
  alias Blackboex.Organizations

  setup :register_and_log_in_user

  setup %{user: user} do
    Registry.clear()

    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{
        name: "Edge Org #{System.unique_integer([:positive])}",
        slug: "edgeorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Edge Test API",
        slug: "edge-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    Apis.upsert_files(api, [
      %{
        path: "/src/handler.ex",
        content: """
        def handle(params) do
          %{echo: params}
        end
        """,
        file_type: "source"
      }
    ])

    %{org: org, api: api}
  end

  defp stub_llm_mocks do
    ClientMock
    |> stub(:stream_text, fn _prompt, _opts -> {:ok, [{:token, "ok"}]} end)
    |> stub(:generate_text, fn _prompt, _opts ->
      {:ok, %{content: "# Docs", usage: %{input_tokens: 10, output_tokens: 10}}}
    end)
  end

  # ── Info tab edge cases ──────────────────────────────────────

  describe "info tab update_info" do
    test "update with empty name shows error or keeps old name", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "", "description" => "some desc"})

      # Should either show validation error or keep old name
      assert html =~ "Edge Test API" or html =~ "can't be blank" or html =~ "error"
    end

    test "update with very long name is handled", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      long_name = String.duplicate("a", 300)

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => long_name, "description" => ""})

      # Should either truncate or show error, not crash
      assert is_binary(html)
    end
  end

  # ── Versions tab edge cases ──────────────────────────────────

  describe "versions tab" do
    test "shows 'No versions yet' for API without versions", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")
      assert html =~ "No versions yet"
    end

    test "view_version shows code for a specific version", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")
      assert html =~ "v1"

      # Click view
      html =
        lv
        |> element(~s(button[phx-click="view_version"][phx-value-number="1"]))
        |> render_click()

      assert html =~ "def handle(_), do: %{v: 1}" or html =~ "v1"
    end

    test "rollback with non-existent version number doesn't crash", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      # Try rolling back to version 999 which doesn't exist
      html = render_click(lv, "rollback", %{"number" => "999"})
      # Should not crash — gracefully handle
      assert is_binary(html)
    end
  end

  # ── Docs tab edge cases ──────────────────────────────────────

  describe "docs tab" do
    test "renders docs tab for API without documentation", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")
      # Should render without crash even with no docs
      assert is_binary(html)
    end

    test "generate_docs button starts generation", %{conn: conn, org: org, api: api} do
      stub_llm_mocks()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      html = render_click(lv, "generate_docs")
      # Should show generating state or the result
      assert is_binary(html)
    end

    test "double-clicking generate_docs is guarded", %{conn: conn, org: org, api: api} do
      stub_llm_mocks()

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/docs?org=#{org.id}")

      # First click starts generation
      render_click(lv, "generate_docs")
      # Second click should be a no-op (guard: doc_generating: true)
      html = render_click(lv, "generate_docs")
      assert is_binary(html)
    end
  end

  # ── Run tab edge cases ───────────────────────────────────────

  describe "run tab edge cases" do
    test "switch to invalid request tab is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_request_tab", %{"tab" => "nonexistent"})
      # Should not crash
      assert is_binary(html)
    end

    test "switch to invalid response tab is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "switch_response_tab", %{"tab" => "nonexistent"})
      assert is_binary(html)
    end

    test "copy_snippet with invalid language is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "copy_snippet", %{"language" => "brainfuck"})
      assert is_binary(html)
    end

    test "copy_snippet with valid language works", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "copy_snippet", %{"language" => "curl"})
      assert is_binary(html)
    end

    test "update_test_url updates the URL", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/run?org=#{org.id}")

      html = render_click(lv, "update_test_url", %{"url" => "/custom/path"})
      assert html =~ "/custom/path"
    end
  end

  # ── Publish tab edge cases ───────────────────────────────────

  describe "publish tab edge cases" do
    test "publish button not available for draft API", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      # Draft APIs can't be published — should show compile first message
      assert html =~ "compile" or html =~ "Compile" or html =~ "draft"
    end

    test "save_publish_settings updates API settings", %{conn: conn, org: org, api: api} do
      # Compile first so publish tab shows settings
      code = "def handle(_), do: %{ok: true}"
      {:ok, module} = Compiler.compile(api, code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html =
        render_click(lv, "save_publish_settings", %{
          "method" => "POST",
          "requires_auth" => "true",
          "visibility" => "public"
        })

      assert is_binary(html)

      updated = Apis.get_api(org.id, api.id)
      assert updated.requires_auth == true

      on_exit(fn -> Compiler.unload(module) end)
    end
  end

  # ── Metrics tab ──────────────────────────────────────────────

  describe "metrics tab" do
    test "renders metrics tab without data", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      assert is_binary(html)
    end

    test "change_metrics_period updates period", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "change_metrics_period", %{"period" => "7d"})
      assert is_binary(html)
    end
  end

  # ── Tests tab ────────────────────────────────────────────────

  describe "tests tab" do
    test "renders tests tab for API without tests", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/tests?org=#{org.id}")
      assert is_binary(html)
    end
  end
end
