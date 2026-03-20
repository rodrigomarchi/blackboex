defmodule BlackboexWeb.ApiLive.PublishFlowTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys
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

  describe "full publish flow" do
    test "compile -> publish -> key created -> URL shown", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Change code and compile via save_and_compile
      lv
      |> render_hook("code_changed", %{"value" => "def handle(_), do: %{published: true}"})

      html = lv |> element("button", "Save & Compile") |> render_click()

      # Verify compilation succeeded
      assert html =~ "Compiled successfully"

      # Remount to pick up fresh api status from DB
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to publish tab
      lv |> element(~s(button[phx-click="switch_tab"][phx-value-tab="publish"])) |> render_click()

      html = render(lv)
      assert html =~ "Publish API"

      # Publish
      html = lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # After publish, we're redirected to keys tab showing the new key
      assert html =~ "published"
      assert html =~ "bb_live_"

      # Verify API key was created
      keys = Keys.list_keys(api.id)
      assert length(keys) == 1
      assert is_nil(hd(keys).revoked_at)

      # Verify API status in DB
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Switch back to publish tab to verify URL is shown
      lv
      |> element(~s(button[phx-click="switch_tab"][phx-value-tab="publish"]))
      |> render_click()

      html = render(lv)
      assert html =~ "/api/puborg/pub-api"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  describe "unpublish flow" do
    test "unpublish -> API removed from registry", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Compile
      lv
      |> render_hook("code_changed", %{"value" => "def handle(_), do: %{published: true}"})

      html = lv |> element("button", "Save & Compile") |> render_click()
      assert html =~ "Compiled successfully"

      # Remount to pick up compiled status
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to publish tab and publish
      lv |> element(~s(button[phx-click="switch_tab"][phx-value-tab="publish"])) |> render_click()
      lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # Verify it's published
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Remount to get fresh published state
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to publish tab
      lv |> element(~s(button[phx-click="switch_tab"][phx-value-tab="publish"])) |> render_click()

      html = render(lv)
      assert html =~ "Unpublish"

      # Unpublish
      html = lv |> element(~s(button[phx-click="unpublish"])) |> render_click()

      assert html =~ "unpublished"

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
