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
    test "renders editor with API name", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Calculator"
    end

    test "shows all tabs in tab bar", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      assert html =~ "Code"
      assert html =~ "Tests"
      assert html =~ "Validation"
      assert html =~ "API Keys"
      assert html =~ "Publish"
      assert html =~ "Info"
    end

    test "shows API info in info tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      html = lv |> render_click("switch_tab", %{"tab" => "info"})

      assert html =~ "calculator"
      assert html =~ "computation"
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
      lv |> render_click("switch_tab", %{"tab" => "run"})
      html = lv |> render_click("switch_tab", %{"tab" => "versions"})

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
      lv |> render_click("switch_tab", %{"tab" => "run"})
      lv |> render_click("switch_tab", %{"tab" => "versions"})

      lv
      |> element(~s(button[phx-click="rollback"][phx-value-number="1"]))
      |> render_click()

      # Flash "Rolled back to v1" is in layout; verify the side-effect
      assert length(Apis.list_versions(api.id)) == 3
    end
  end
end
