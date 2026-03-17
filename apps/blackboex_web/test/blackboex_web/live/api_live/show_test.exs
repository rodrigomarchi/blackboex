defmodule BlackboexWeb.ApiLive.ShowTest do
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

    # Set org in session
    %{org: org}
  end

  defp create_api_with_code(org, user) do
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

    api
  end

  describe "show page" do
    test "displays API details", %{conn: conn, org: org, user: user} do
      api = create_api_with_code(org, user)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}?org=#{org.id}")

      assert html =~ "Calculator"
      assert html =~ "draft"
    end

    test "shows Compile button when API has source_code", %{conn: conn, org: org, user: user} do
      api = create_api_with_code(org, user)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}?org=#{org.id}")

      assert html =~ "Compile"
    end

    test "compiling API shows success badge", %{conn: conn, org: org, user: user} do
      api = create_api_with_code(org, user)

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}?org=#{org.id}")

      html = lv |> element("button", "Compile") |> render_click()

      assert html =~ "compiled"
      assert html =~ "/api/testorg/calculator"

      on_exit(fn ->
        module = Compiler.module_name_for(api)
        Compiler.unload(module)
      end)
    end

    test "rejects access to API from another organization", %{conn: conn, user: _user} do
      # Create another user's org and API
      other_user = Blackboex.AccountsFixtures.user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org",
          slug: "otherorg"
        })

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Secret API",
          slug: "secret",
          template_type: "computation",
          organization_id: other_org.id,
          user_id: other_user.id,
          source_code: "def handle(_), do: %{secret: true}"
        })

      # Try to access via org param — should redirect since user has no membership
      assert {:error, {:live_redirect, %{to: "/apis", flash: %{"error" => "API not found"}}}} =
               live(conn, ~p"/apis/#{other_api.id}?org=#{other_org.id}")
    end

    test "compiling insecure code shows errors", %{conn: conn, org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Bad API",
          slug: "bad-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: """
          def handle(_params) do
            File.read("/etc/passwd")
          end
          """
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}?org=#{org.id}")

      html = lv |> element("button", "Compile") |> render_click()

      assert html =~ "File"
      assert html =~ "blocked"
    end
  end
end
