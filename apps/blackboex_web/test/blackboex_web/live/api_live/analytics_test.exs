defmodule BlackboexWeb.ApiLive.AnalyticsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis

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

  describe "analytics page" do
    test "redirects to editor", %{conn: conn, api: api} do
      assert {:error, {:live_redirect, %{to: "/apis/" <> _rest}}} =
               live(conn, ~p"/apis/#{api.id}/analytics")
    end
  end
end
