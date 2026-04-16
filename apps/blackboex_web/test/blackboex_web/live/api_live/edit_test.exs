defmodule BlackboexWeb.ApiLive.EditTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry

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
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    Apis.upsert_files(api, [
      %{
        path: "/src/handler.ex",
        content: """
        def handle(params) do
          a = Map.get(params, "a", 0)
          b = Map.get(params, "b", 0)
          %{result: a + b}
        end
        """,
        file_type: "source"
      }
    ])

    %{org: org, api: api}
  end

  describe "mount" do
    test "renders editor with API name", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      assert html =~ "Calculator"
    end

    test "shows all tabs in tab bar", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      assert html =~ "Chat"
      assert html =~ "Validation"
      assert html =~ "Run"
      assert html =~ "Metrics"
      assert html =~ "Publish"
      assert html =~ "Info"
      # "API Keys" now appears in collapsed sidebar tooltip, so we check
      # that non-editor tabs don't appear in the editor tab bar specifically
      refute html =~ "Versions"
    end

    test "shows API info in info tab", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "calculator"
      assert html =~ "computation"
    end
  end

  describe "versions" do
    test "shows version history in publish tab", %{conn: conn, org: org, api: api, user: user} do
      # Create a version first
      Apis.create_version(api, %{
        code: "def handle(_), do: %{v: 1}",
        source: "generation",
        created_by_id: user.id
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

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
          project_id: Blackboex.Projects.get_default_project(other_org.id).id,
          user_id: other_user.id
        })

      assert {:error, {:live_redirect, %{to: "/apis", flash: %{"error" => "API not found"}}}} =
               live(conn, ~p"/apis/#{other_api.id}/edit/chat?org=#{other_org.id}")
    end
  end

  describe "view_version" do
    test "view_version shows selected version", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html =
        lv
        |> element(~s(button[phx-click="view_version"][phx-value-number="1"]))
        |> render_click()

      assert html =~ "v1"
    end
  end
end
