defmodule BlackboexWeb.ApiLive.EditTest do
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
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Calculator",
        slug: "calculator",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: """
        def handle(params) do
          a = Map.get(params, "a", 0)
          b = Map.get(params, "b", 0)
          %{result: a + b}
        end
        """
      })

    %{org: org, api: api}
  end

  describe "mount" do
    test "renders editor with API code loaded", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Calculator"
      assert html =~ "Code Editor"
      assert html =~ "Save"
      assert html =~ "Save &amp; Compile"
    end

    test "shows tabs: Info, Versions, Test", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Info"
      assert html =~ "Versions"
      assert html =~ "Test"
    end

    test "shows API info in Info tab", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "calculator"
      assert html =~ "computation"
    end
  end

  describe "save" do
    test "saves code and creates version", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Simulate code change event
      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{saved: true}"})

      lv |> element("button[phx-click=save]") |> render_click()

      # Flash is rendered by the app layout; verify the side-effect instead
      versions = Apis.list_versions(api.id)
      assert length(versions) == 1
      assert hd(versions).source == "manual_edit"
    end
  end

  describe "save and compile" do
    test "saves, compiles, and shows success", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{compiled: true}"})

      lv |> element("button", "Save & Compile") |> render_click()
      html = render(lv)

      # "Compiled successfully" badge is rendered in the LV template
      assert html =~ "Compiled successfully"
      assert html =~ "/api/testorg/calculator"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end

    test "shows errors for insecure code", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv
      |> render_hook("code_changed", %{
        "value" => "def handle(_), do: File.read(\"/etc/passwd\")"
      })

      html = lv |> element("button", "Save & Compile") |> render_click()

      assert html =~ "failed"
      assert html =~ "File"
    end
  end

  describe "versions tab" do
    test "shows version history after save", %{conn: conn, org: org, api: api, user: user} do
      # Create a version first
      Apis.create_version(api, %{
        code: "def handle(_), do: %{v: 1}",
        source: "generation",
        created_by_id: user.id
      })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> element("button", "Versions") |> render_click()

      assert html =~ "v1"
      assert html =~ "generation"
    end
  end

  describe "authorization" do
    test "rejects access to API from another org", %{conn: conn} do
      other_user = Blackboex.AccountsFixtures.user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other", slug: "other"})

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Secret",
          slug: "secret",
          template_type: "computation",
          organization_id: other_org.id,
          user_id: other_user.id,
          source_code: "def handle(_), do: :secret"
        })

      assert {:error, {:live_redirect, %{to: "/apis", flash: %{"error" => "API not found"}}}} =
               live(conn, ~p"/apis/#{other_api.id}/edit?org=#{other_org.id}")
    end
  end

  describe "no-change save" do
    test "skips save when code hasn't changed", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Don't change code, just click save
      lv |> element("button[phx-click=save]") |> render_click()

      # Flash "No changes" is in layout; verify no version was created
      assert Apis.list_versions(api.id) == []
    end
  end

  describe "compile state management" do
    test "compile success badge clears when code changes", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Compile first
      lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{ok: true}"})
      html = lv |> element("button", "Save & Compile") |> render_click()
      assert html =~ "Compiled successfully"

      # Now change code — badge should disappear
      html =
        lv |> render_hook("code_changed", %{"value" => "def handle(_), do: %{changed: true}"})

      refute html =~ "Compiled successfully"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end
  end

  describe "rollback" do
    test "creates new version with old code", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to versions tab
      lv |> element("button", "Versions") |> render_click()

      lv
      |> element(~s(button[phx-click="rollback"][phx-value-number="1"]))
      |> render_click()

      # Flash "Rolled back to v1" is in layout; verify the side-effect
      assert length(Apis.list_versions(api.id)) == 3
    end
  end
end
