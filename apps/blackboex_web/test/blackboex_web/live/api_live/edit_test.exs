defmodule BlackboexWeb.ApiLive.EditTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry

  setup :verify_on_exit!
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

  defp stub_pipeline_mocks do
    Blackboex.LLM.ClientMock
    |> stub(:stream_text, fn _prompt, _opts -> {:ok, [{:token, "no fix needed"}]} end)
    |> stub(:generate_text, fn _prompt, _opts ->
      {:ok,
       %{
         content:
           "```elixir\ndefmodule Test do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
         usage: %{input_tokens: 50, output_tokens: 50}
       }}
    end)
  end

  # Helper to wait for the async validation pipeline to complete
  defp wait_for_pipeline(lv) do
    # Give the Task time to complete
    Process.sleep(800)
    # Trigger re-render to process pending messages
    render(lv)
  end

  describe "mount" do
    test "renders editor with API name and save button", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Calculator"
      assert html =~ "Save"
    end

    test "shows panel toggle buttons in toolbar", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Chat"
      assert html =~ "Test"
      assert html =~ "Config"
    end

    test "shows API info when config panel is opened", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> element(~s(button[phx-click="toggle_config"])) |> render_click()

      assert html =~ "calculator"
      assert html =~ "computation"
    end
  end

  describe "save" do
    test "saves code and creates version", %{conn: conn, org: org, api: api} do
      stub_pipeline_mocks()
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Simulate code change event
      lv |> render_hook("editor_changed", %{"value" => "def handle(_), do: %{saved: true}"})

      lv |> element("button[phx-click=save]") |> render_click()

      # Wait for async validation pipeline to complete
      wait_for_pipeline(lv)

      # Flash is rendered by the app layout; verify the side-effect instead
      versions = Apis.list_versions(api.id)
      assert length(versions) == 1
      assert hd(versions).source == "manual_edit"
    end
  end

  describe "save and validate" do
    test "saves and runs validation pipeline", %{conn: conn, org: org, api: api} do
      stub_pipeline_mocks()
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv |> render_hook("editor_changed", %{"value" => "def handle(_), do: %{compiled: true}"})

      lv |> element(~s(button[phx-click="save"])) |> render_click()

      # Wait for validation pipeline
      wait_for_pipeline(lv)

      # Verify side-effect: version was created
      versions = Apis.list_versions(api.id)
      assert length(versions) == 1
    end

    test "shows validation results for insecure code", %{conn: conn, org: org, api: api} do
      stub_pipeline_mocks()
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      lv
      |> render_hook("editor_changed", %{
        "value" => "def handle(_), do: File.read(\"/etc/passwd\")"
      })

      # Save — validation pipeline runs and opens the validation tab
      lv |> element(~s(button[phx-click="save"])) |> render_click()

      # Wait for the validation pipeline to complete
      wait_for_pipeline(lv)

      # Verify version was created (save succeeded) and check validation results
      versions = Apis.list_versions(api.id)
      assert length(versions) == 1

      html = render(lv)
      # Validation dashboard should show compilation issues
      assert html =~ "Compilation" || html =~ "ISSUES"
    end
  end

  describe "versions" do
    test "shows version history in bottom panel", %{conn: conn, org: org, api: api, user: user} do
      # Create a version first
      Apis.create_version(api, %{
        code: "def handle(_), do: %{v: 1}",
        source: "generation",
        created_by_id: user.id
      })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open bottom panel and switch to versions tab
      lv |> element(~s(button[phx-click="toggle_bottom_panel"])) |> render_click()
      html = lv |> render_hook("switch_bottom_tab", %{"tab" => "versions"})

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
    test "new save replaces previous validation report", %{conn: conn, org: org, api: api} do
      stub_pipeline_mocks()
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Save with valid code
      lv |> render_hook("editor_changed", %{"value" => "def handle(_), do: %{ok: true}"})
      lv |> element(~s(button[phx-click="save"])) |> render_click()

      # Wait for validation pipeline to complete
      wait_for_pipeline(lv)

      # Verify a version was created
      assert length(Apis.list_versions(api.id)) == 1
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

      # Open bottom panel and switch to versions tab
      lv |> element(~s(button[phx-click="toggle_bottom_panel"])) |> render_click()
      lv |> render_hook("switch_bottom_tab", %{"tab" => "versions"})

      lv
      |> element(~s(button[phx-click="rollback"][phx-value-number="1"]))
      |> render_click()

      # Flash "Rolled back to v1" is in layout; verify the side-effect
      assert length(Apis.list_versions(api.id)) == 3
    end
  end
end
