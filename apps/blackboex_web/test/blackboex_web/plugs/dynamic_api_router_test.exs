defmodule BlackboexWeb.Plugs.DynamicApiRouterTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  import Blackboex.AccountsFixtures

  setup do
    Registry.clear()

    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    %{user: user, org: org}
  end

  defp create_and_compile_api(org, user, attrs \\ %{}) do
    defaults = %{
      name: "Calculator API",
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
    }

    api_attrs = Map.merge(defaults, attrs)
    {:ok, api} = Apis.create_api(api_attrs)
    {:ok, module} = Compiler.compile(api, api.source_code)
    {:ok, api} = Apis.update_api(api, %{status: "compiled"})

    Registry.register(api.id, module,
      org_slug: org.slug,
      slug: api.slug
    )

    on_exit(fn -> Compiler.unload(module) end)

    {api, module}
  end

  describe "requests to /api/:username/:slug" do
    test "returns 200 for compiled API", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/calculator", Jason.encode!(%{"a" => 1, "b" => 2}))

      assert json_response(conn, 200) == %{"result" => 3}
    end

    test "returns 404 for nonexistent API", %{conn: conn} do
      conn = get(conn, "/api/nobody/nothing")

      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "returns 404 for draft API", %{conn: conn, org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Draft API",
          slug: "draft-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      # Draft APIs are NOT registered in Registry
      assert api.status == "draft"

      conn = get(conn, "/api/testorg/draft-api")
      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "returns valid JSON response", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/calculator", Jason.encode!(%{"a" => 5, "b" => 10}))

      response = json_response(conn, 200)
      assert is_map(response)
      assert response["result"] == 15
    end

    test "returns 500 for handler errors", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user, %{
        name: "Error API",
        slug: "error-api",
        source_code: """
        def handle(_params) do
          raise "intentional error"
        end
        """
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/error-api", Jason.encode!(%{}))

      response = json_response(conn, 500)
      assert response["error"] =~ "execution" or response["error"] =~ "handler error"
    end

    test "returns 404 for /api with no segments", %{conn: conn} do
      conn = get(conn, "/api")
      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "returns 404 for /api/username with only one segment", %{conn: conn} do
      conn = get(conn, "/api/testorg")
      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "sub-path is forwarded correctly to module", %{conn: conn, org: org, user: user} do
      # CRUD APIs use sub-paths like /:id
      create_and_compile_api(org, user, %{
        name: "CRUD API",
        slug: "crud-api",
        template_type: "crud",
        source_code: """
        def handle_list(_params), do: %{items: []}
        def handle_get(id, _params), do: %{id: id}
        def handle_create(params), do: %{created: true, data: params}
        def handle_update(id, params), do: %{id: id, data: params}
        def handle_delete(id), do: %{id: id, deleted: true}
        """
      })

      conn = get(conn, "/api/testorg/crud-api/some-item-id")
      assert json_response(conn, 200)["id"] == "some-item-id"
    end

    test "POST with invalid JSON raises ParseError (caught by Endpoint)", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user)

      # Malformed JSON is caught by Phoenix Endpoint's Plug.Parsers before
      # reaching DynamicApiRouter — this is standard Phoenix behavior
      assert_raise Plug.Parsers.ParseError, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/calculator", "not valid json{{{")
      end
    end

    test "GET /api/:username/:slug returns info for computation API", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user)

      conn = get(conn, "/api/testorg/calculator")

      assert json_response(conn, 200) == %{"status" => "ok", "type" => "computation"}
    end
  end

  # ── shutting down ────────────────────────────────────────────

  describe "shutting down" do
    test "returns 503 when registry is shutting down", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      # Put registry in shutdown mode
      :persistent_term.put(:api_registry_shutting_down, true)

      on_exit(fn ->
        :persistent_term.put(:api_registry_shutting_down, false)
      end)

      conn = get(conn, "/api/testorg/calculator")
      assert json_response(conn, 503) == %{"error" => "Service is shutting down"}

      # Restore immediately for remaining tests in this run
      :persistent_term.put(:api_registry_shutting_down, false)
    end
  end

  # ── docs paths ───────────────────────────────────────────────

  describe "docs paths" do
    test "GET /api/:org/:slug/docs serves Swagger UI", %{conn: conn, org: org, user: user} do
      {api, _module} = create_and_compile_api(org, user)
      # Ensure API has some documentation
      Apis.update_api(api, %{documentation_md: "# Calculator\nAdds numbers."})

      conn = get(conn, "/api/testorg/calculator/docs")

      # Swagger UI returns HTML
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end

    test "GET /api/:org/:slug/openapi.json returns JSON spec", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user)

      conn = get(conn, "/api/testorg/calculator/openapi.json")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end

    test "GET /api/:org/:slug/openapi.yaml returns YAML spec", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user)

      conn = get(conn, "/api/testorg/calculator/openapi.yaml")

      assert conn.status == 200
    end
  end

  # ��─ handler edge cases ───────────────────────────────────────

  describe "handler edge cases" do
    test "returns appropriate error for handler returning non-standard response", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user, %{
        name: "Nil API",
        slug: "nil-api",
        source_code: """
        def handle(_params) do
          nil
        end
        """
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/nil-api", Jason.encode!(%{}))

      # Should get a response (either 200 with nil-ish body or 500)
      assert conn.status in [200, 500]
    end

    test "handler return value is serialized as-is (status field is data, not HTTP status)", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user, %{
        name: "Status Map API",
        slug: "status-map-api",
        source_code: """
        def handle(_params) do
          %{status: 422, body: %{error: "Validation failed"}}
        end
        """
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/status-map-api", Jason.encode!(%{}))

      # Module builder hardcodes HTTP 200 — handler's :status key is just data
      response = json_response(conn, 200)
      assert response["status"] == 422
      assert response["body"]["error"] == "Validation failed"
    end

    test "handles empty JSON body", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/calculator", Jason.encode!(%{}))

      # Empty params: a and b default to 0
      assert json_response(conn, 200) == %{"result" => 0}
    end

    test "returns 404 for nonexistent org slug", %{conn: conn} do
      conn = get(conn, "/api/nonexistent-org/some-api")
      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "returns 404 for valid org but nonexistent slug", %{conn: conn, org: _org} do
      conn = get(conn, "/api/testorg/nonexistent-api")
      assert json_response(conn, 404) == %{"error" => "API not found"}
    end
  end

  # ── on-demand compilation ────────────────────────────────────

  describe "on-demand compilation from DB" do
    test "compiles and serves API not in registry", %{conn: conn, org: org, user: user} do
      # Create a compiled API but DON'T register it in the registry
      {:ok, api} =
        Apis.create_api(%{
          name: "Unregistered API",
          slug: "unregistered-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: """
          def handle(_params) do
            %{hello: "world"}
          end
          """
        })

      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      # Don't register — DynamicApiRouter should compile on-demand
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/unregistered-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"hello" => "world"}
    end
  end
end
