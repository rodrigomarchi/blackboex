defmodule BlackboexWeb.ApiLive.AnalyticsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias BlackboexWeb.ApiLive.Analytics

  describe "render" do
    test "renders an empty div" do
      assigns = %{__changed__: nil}

      html =
        Phoenix.LiveViewTest.render_component(&Analytics.render/1, assigns)

      assert html =~ "<div"
    end
  end

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/apis/#{Ecto.UUID.generate()}/analytics")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    setup %{user: user} do
      {:ok, %{organization: org}} =
        Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

      {:ok, api} =
        Apis.create_api(%{
          name: "Analytics API",
          slug: "analytics-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(_), do: %{ok: true}"
        })

      %{org: org, api: api}
    end

    test "redirects to editor for the correct API", %{conn: conn, api: api} do
      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               live(conn, ~p"/apis/#{api.id}/analytics")

      assert redirect_path == "/apis/#{api.id}/edit"
    end

    test "redirects to login for unknown API ID when unauthenticated", %{conn: _conn} do
      bare_conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(bare_conn, ~p"/apis/#{Ecto.UUID.generate()}/analytics")
    end
  end
end
