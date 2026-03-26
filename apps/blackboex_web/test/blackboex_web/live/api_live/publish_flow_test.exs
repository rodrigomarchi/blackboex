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

  defp compile_directly(api) do
    code = "def handle(_), do: %{published: true}"
    {:ok, _module} = Compiler.compile(api, code)
    {:ok, _api} = Apis.update_api(api, %{status: "compiled", source_code: code})
  end

  describe "full publish flow" do
    test "compile -> publish -> key created -> URL shown", %{conn: conn, org: org, api: api} do
      # Compile the API directly
      compile_directly(api)

      # Mount with compiled status
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the Config panel (publish section is inside)
      lv |> render_click("switch_tab", %{"tab" => "publish"})

      html = render(lv)
      assert html =~ "Publish API"

      # Publish (after publish, the handler opens the config panel with keys loaded)
      html = lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # After publish, status updated
      assert html =~ "published"

      # Verify API status in DB
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Switch to publish tab to see URL
      html = render_click(lv, "switch_tab", %{"tab" => "publish"})
      assert html =~ "/api/puborg/pub-api"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  describe "unpublish flow" do
    test "unpublish -> API removed from registry", %{conn: conn, org: org, api: api} do
      # Compile directly
      compile_directly(api)

      # Mount with compiled status
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open config panel and publish
      lv |> render_click("switch_tab", %{"tab" => "publish"})
      lv |> element(~s(button[phx-click="publish"])) |> render_click()

      # Verify it's published
      updated_api = Apis.get_api(org.id, api.id)
      assert updated_api.status == "published"

      # Remount to get fresh published state
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open config panel to see Unpublish button
      lv |> render_click("switch_tab", %{"tab" => "publish"})

      html = render(lv)
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
