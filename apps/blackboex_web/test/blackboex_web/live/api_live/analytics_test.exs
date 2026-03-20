defmodule BlackboexWeb.ApiLive.AnalyticsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis.Api
  alias Blackboex.Organizations

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  defp create_api(%{user: user}) do
    [org] = Organizations.list_user_organizations(user)

    {:ok, api} =
      %Api{}
      |> Api.changeset(%{
        name: "Analytics Test API",
        slug: "analytics-test",
        description: "Test",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })
      |> Blackboex.Repo.insert()

    %{api: api, org: org}
  end

  describe "mount" do
    setup [:create_api]

    test "renders analytics page", %{conn: conn, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/analytics")

      assert html =~ "Analytics"
      assert html =~ api.name
      assert html =~ "No analytics data available"
    end

    test "shows period selector buttons", %{conn: conn, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/analytics")

      assert html =~ "24h"
      assert html =~ "7d"
      assert html =~ "30d"
    end
  end

  describe "period change" do
    setup [:create_api]

    test "changes period on click", %{conn: conn, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/analytics")

      html = lv |> element("button", "30d") |> render_click()
      assert html =~ "No analytics data available"
    end
  end

  describe "access control" do
    test "redirects when API not found", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      {:error, {:live_redirect, %{to: "/apis"}}} = live(conn, ~p"/apis/#{fake_id}/analytics")
    end
  end
end
