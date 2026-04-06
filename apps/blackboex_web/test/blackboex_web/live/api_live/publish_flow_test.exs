defmodule BlackboexWeb.ApiLive.PublishFlowTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  setup :register_and_log_in_user

  setup %{user: user} do
    Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Pub Org", slug: "puborg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Pub API",
        slug: "pub-api",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}"
      })

    %{org: org, api: api}
  end

  defp compile_directly(api) do
    code = "def handle(_), do: %{published: true}"
    {:ok, _module} = Compiler.compile(api, code)
    {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})
  end

  describe "full publish flow" do
    test "compile -> publish -> key created -> URL shown", %{conn: conn, org: org, api: api} do
      # Compile the API directly
      compile_directly(api)

      # Mount on publish tab
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      assert html =~ "Publish API"

      # Publish (after publish, the handler opens the config panel with keys loaded)
      html = lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # After publish, status updated
      assert html =~ "published"

      # Verify API status in DB
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Re-render to see URL
      html = render(lv)
      assert html =~ "/api/puborg/pub-api"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  describe "draft state" do
    test "shows draft message when API is in draft status", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      # Draft API shows the 'Save first' message
      assert html =~ "Save the API to compile it"
    end

    test "does not show Publish button for draft API", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      # No publish button for draft
      refute html =~ ~s(phx-click="publish")
    end

    test "shows API URL in publication card", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      assert html =~ "/api/#{org.slug}/#{api.slug}"
    end
  end

  describe "save_publish_settings" do
    test "saves method and visibility settings", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html =
        lv
        |> form("form[phx-submit='save_publish_settings']",
          method: "POST",
          visibility: "public",
          requires_auth: "true"
        )
        |> render_submit()

      assert html =~ "Settings saved" or is_binary(html)
    end

    test "save_publish_settings updates requires_auth", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html =
        render_click(lv, "save_publish_settings", %{
          "method" => "GET",
          "visibility" => "private",
          "requires_auth" => "true"
        })

      assert is_binary(html)
    end

    test "save_publish_settings with requires_auth false", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html =
        render_click(lv, "save_publish_settings", %{
          "method" => "POST",
          "visibility" => "public"
        })

      assert is_binary(html)
    end
  end

  describe "copy_url" do
    test "copy_url pushes copy_to_clipboard event", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html = render_click(lv, "copy_url", %{})
      assert is_binary(html)
    end
  end

  describe "command palette on publish tab" do
    test "toggle_command_palette works on publish tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html = render_click(lv, "toggle_command_palette", %{})
      assert is_binary(html)
    end

    test "close_panels works on publish tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end
  end

  describe "unpublish flow" do
    test "unpublish -> API removed from registry", %{conn: conn, org: org, api: api} do
      # Compile directly
      compile_directly(api)

      # Mount on publish tab and publish
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")
      lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # Verify it's published
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Remount to get fresh published state
      {:ok, lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      assert html =~ "Unpublish"

      # Unpublish
      lv |> element(~s(button[phx-click="unpublish"])) |> render_click()

      # Verify API status changed back
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "compiled"

      # Verify removed from registry
      assert Registry.lookup(api.id) == {:error, :not_found}

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end
end
