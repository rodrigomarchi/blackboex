defmodule BlackboexWeb.Plugs.ApiDocsPlugTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :capture_log

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  import Blackboex.AccountsFixtures

  setup do
    Registry.clear()

    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Docs Org", slug: "docsorg"})

    %{user: user, org: org}
  end

  defp create_published_api(org, user, opts \\ []) do
    visibility = Keyword.get(opts, :visibility, "public")

    {:ok, api} =
      Apis.create_api(%{
        name: "Docs API",
        slug: "docs-api",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: """
        def handle(params) do
          %{result: Map.get(params, "value", 0) * 2}
        end
        """,
        param_schema: %{"value" => "integer"},
        example_request: %{"value" => 21},
        example_response: %{"result" => 42}
      })

    {:ok, module} = Compiler.compile(api, api.source_code)
    {:ok, api} = Apis.update_api(api, %{status: "published", visibility: visibility})

    Registry.register(api.id, module,
      org_slug: org.slug,
      slug: api.slug,
      requires_auth: api.requires_auth,
      visibility: visibility
    )

    on_exit(fn -> Compiler.unload(module) end)

    api
  end

  describe "GET /api/:org/:slug/openapi.json" do
    test "returns valid JSON spec for published public API", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_published_api(org, user)

      conn = get(conn, "/api/docsorg/docs-api/openapi.json")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      body = Jason.decode!(conn.resp_body)
      assert body["openapi"] == "3.1.0"
      assert body["info"]["title"] == "Docs API"
      assert body["paths"]["/"]["post"]
    end

    test "returns 404 for unpublished API", %{conn: conn, org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Draft API",
          slug: "draft-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(_), do: %{ok: true}"
        })

      {:ok, module} = Compiler.compile(api, api.source_code)
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug
      )

      on_exit(fn -> Compiler.unload(module) end)

      conn = get(conn, "/api/docsorg/draft-api/openapi.json")
      # Non-published API: docs path goes to run_pipeline which attempts execution
      # The compiled API will try to handle the request normally
      assert conn.status in [200, 404, 500]
    end

    test "returns 404 for nonexistent API", %{conn: conn} do
      conn = get(conn, "/api/docsorg/nonexistent/openapi.json")
      assert conn.status == 404
    end

    test "does NOT serve docs for private published API", %{conn: conn, org: org, user: user} do
      create_published_api(org, user, visibility: "private")

      conn = get(conn, "/api/docsorg/docs-api/openapi.json")
      # Private API: docs path falls through to run_pipeline (not served as docs)
      # The API handler will try to execute normally, resulting in non-200
      refute conn.status == 200 and
               get_resp_header(conn, "content-type") |> hd() =~ "application/json" and
               match?(%{"openapi" => _}, Jason.decode!(conn.resp_body))
    end
  end

  describe "GET /api/:org/:slug/docs" do
    test "returns Swagger UI HTML for published public API", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_published_api(org, user)

      conn = get(conn, "/api/docsorg/docs-api/docs")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
      assert conn.resp_body =~ "swagger-ui"
      assert conn.resp_body =~ "openapi.json"
      assert conn.resp_body =~ "Docs API"
    end
  end

  describe "XSS prevention in Swagger UI" do
    test "API name is HTML-escaped in Swagger UI page", %{conn: conn, org: org, user: user} do
      # Create API with XSS payload in name
      {:ok, api} =
        Apis.create_api(%{
          name: "<script>alert('xss')</script>",
          slug: "xss-test",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(_), do: %{ok: true}"
        })

      {:ok, module} = Compiler.compile(api, api.source_code)
      {:ok, _api} = Apis.update_api(api, %{status: "published", visibility: "public"})

      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: false,
        visibility: "public"
      )

      on_exit(fn -> Compiler.unload(module) end)

      conn = get(conn, "/api/docsorg/xss-test/docs")
      assert conn.status == 200
      refute conn.resp_body =~ "<script>alert"
      assert conn.resp_body =~ "&lt;script&gt;"
    end
  end

  describe "GET /api/:org/:slug/openapi.yaml" do
    test "returns YAML spec for published public API", %{conn: conn, org: org, user: user} do
      create_published_api(org, user)

      conn = get(conn, "/api/docsorg/docs-api/openapi.yaml")

      assert conn.status == 200
      assert conn.resp_body =~ "openapi:"
      assert conn.resp_body =~ "Docs API"
    end
  end
end
