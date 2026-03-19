defmodule BlackboexWeb.PublicApiControllerTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias Blackboex.Apis

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Public Org"})

    %{user: user, org: org}
  end

  describe "GET /p/:org_slug/:api_slug" do
    test "renders public page for published public API", %{conn: conn, user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Public API",
          description: "A public API",
          status: "published",
          visibility: "public",
          requires_auth: false,
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      conn = get(conn, ~p"/p/#{org.slug}/#{api.slug}")
      assert html_response(conn, 200) =~ "Public API"
      assert html_response(conn, 200) =~ "A public API"
      assert html_response(conn, 200) =~ org.name
    end

    test "returns 404 for private published API", %{conn: conn, user: user, org: org} do
      {:ok, _api} =
        Apis.create_api(%{
          name: "Private API",
          status: "published",
          visibility: "private",
          organization_id: org.id,
          user_id: user.id
        })

      conn = get(conn, ~p"/p/#{org.slug}/private-api")
      assert html_response(conn, 404)
    end

    test "returns 404 for draft API", %{conn: conn, user: user, org: org} do
      {:ok, _api} =
        Apis.create_api(%{
          name: "Draft API",
          organization_id: org.id,
          user_id: user.id
        })

      conn = get(conn, ~p"/p/#{org.slug}/draft-api")
      assert html_response(conn, 404)
    end

    test "returns 404 for non-existent API", %{conn: conn, org: org} do
      conn = get(conn, ~p"/p/#{org.slug}/nonexistent")
      assert html_response(conn, 404)
    end

    test "returns 404 for non-existent org", %{conn: conn} do
      conn = get(conn, ~p"/p/noorg/noapi")
      assert html_response(conn, 404)
    end

    test "escapes XSS payload in name and description", %{conn: conn, user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "<script>alert('xss')</script>",
          description: "<img src=x onerror=alert(1)>",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      conn = get(conn, ~p"/p/#{org.slug}/#{api.slug}")
      body = html_response(conn, 200)
      # Script tags must be escaped, not rendered as HTML
      refute body =~ "<script>alert"
      refute body =~ "<img src=x"
      # Escaped versions should be present
      assert body =~ "&lt;script&gt;"
      assert body =~ "&lt;img"
    end

    test "shows auth info when requires_auth is true", %{conn: conn, user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Auth API",
          status: "published",
          visibility: "public",
          requires_auth: true,
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      conn = get(conn, ~p"/p/#{org.slug}/#{api.slug}")
      assert html_response(conn, 200) =~ "API Key required"
      assert html_response(conn, 200) =~ "YOUR_API_KEY"
    end
  end
end
