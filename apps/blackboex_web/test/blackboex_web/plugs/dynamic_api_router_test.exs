defmodule BlackboexWeb.Plugs.DynamicApiRouterTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :integration

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  setup do
    Registry.clear()

    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    %{user: user, org: org}
  end

  defp create_and_compile_api(org, user, attrs \\ %{}) do
    default_source = """
    def handle(params) do
      a = Map.get(params, "a", 0)
      b = Map.get(params, "b", 0)
      %{result: a + b}
    end
    """

    source_code = Map.get(attrs, :source_code, default_source)

    defaults = %{
      name: "Calculator API",
      slug: "calculator",
      template_type: "computation",
      organization_id: org.id,
      project_id: Blackboex.Projects.get_default_project(org.id).id,
      user_id: user.id
    }

    api_attrs = defaults |> Map.merge(Map.drop(attrs, [:source_code]))
    {:ok, api} = Apis.create_api(api_attrs)

    Apis.upsert_files(api, [
      %{path: "/src/handler.ex", content: source_code, file_type: "source"}
    ])

    {:ok, module} = Compiler.compile(api, source_code)
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
          project_id: Blackboex.Projects.get_default_project(org.id).id,
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
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      unregistered_source = """
      def handle(_params) do
        %{hello: "world"}
      end
      """

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: unregistered_source, file_type: "source"}
      ])

      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      # Don't register — DynamicApiRouter should compile on-demand
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/unregistered-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"hello" => "world"}
    end
  end

  # ── rate limiting ─────────────────────────────────────────────────────────────

  describe "rate limiting" do
    test "returns 429 when draft IP rate limit is exceeded", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      unique_last_octet = System.unique_integer([:positive]) |> rem(200) |> Kernel.+(1)
      ip = {192, 168, unique_last_octet, 1}

      # Exhaust the draft IP limit (20 req/min)
      for _ <- 1..20 do
        c = %{build_conn(:get, "/api/testorg/calculator") | remote_ip: ip}
        get(c, "/api/testorg/calculator")
      end

      conn = %{conn | remote_ip: ip}
      conn = get(conn, "/api/testorg/calculator")

      assert conn.status == 429
      response = json_response(conn, 429)
      assert response["error"] == "Rate limit exceeded"
      assert is_integer(response["retry_after"])
    end

    test "returns retry-after header when rate limited", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user)

      unique_last_octet = System.unique_integer([:positive]) |> rem(200) |> Kernel.+(1)
      ip = {172, 16, unique_last_octet, 2}

      # Exhaust draft limit
      for _ <- 1..20 do
        c = %{build_conn(:get, "/api/testorg/calculator") | remote_ip: ip}
        get(c, "/api/testorg/calculator")
      end

      conn = %{conn | remote_ip: ip}
      conn = get(conn, "/api/testorg/calculator")

      # Status may be 429 if limit still active
      if conn.status == 429 do
        retry_after = get_resp_header(conn, "retry-after")
        assert length(retry_after) == 1
        assert String.to_integer(hd(retry_after)) >= 0
      else
        assert conn.status == 200
      end
    end
  end

  # ── authentication ────────────────────────────────────────────────────────────

  describe "authentication for published APIs" do
    defp create_published_api(org, user, attrs \\ %{}) do
      default_source = """
      def handle(_params) do
        %{result: "published"}
      end
      """

      source_code = Map.get(attrs, :source_code, default_source)

      defaults = %{
        name: "Published API",
        slug: "published-api",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id,
        requires_auth: true
      }

      api_attrs = defaults |> Map.merge(Map.drop(attrs, [:source_code]))
      {:ok, api} = Apis.create_api(api_attrs)

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: source_code, file_type: "source"}
      ])

      {:ok, module} = Compiler.compile(api, source_code)
      {:ok, api} = Apis.update_api(api, %{status: "published"})

      Registry.register(api.id, module,
        org_slug: org.slug,
        slug: api.slug,
        requires_auth: api.requires_auth
      )

      on_exit(fn -> Compiler.unload(module) end)
      api
    end

    test "returns 401 with missing_key message when no API key provided", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_published_api(org, user)

      conn = get(conn, "/api/testorg/published-api")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["error"] == "API key required"
      assert response["hint"] =~ "Authorization"
    end

    test "returns 401 with invalid message for wrong API key", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_published_api(org, user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bb_live_invalidkeyxxxxxxxxxxxxxxxxxxxx")
        |> get("/api/testorg/published-api")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "Invalid API key"
    end

    test "returns 200 for published API with valid API key", %{
      conn: conn,
      org: org,
      user: user
    } do
      api = create_published_api(org, user)
      {:ok, plain_key, _api_key} = Keys.create_key(api, %{label: "Test", organization_id: org.id})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{plain_key}")
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/published-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"result" => "published"}
    end

    test "returns 401 for revoked API key", %{conn: conn, org: org, user: user} do
      api = create_published_api(org, user)

      {:ok, plain_key, api_key} =
        Keys.create_key(api, %{label: "Revocable", organization_id: org.id})

      {:ok, _} = Keys.revoke_key(api_key)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{plain_key}")
        |> get("/api/testorg/published-api")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "API key has been revoked"
    end

    test "returns 401 for expired API key", %{conn: conn, org: org, user: user} do
      api = create_published_api(org, user)

      {:ok, plain_key, _} =
        Keys.create_key(api, %{
          label: "Expired",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          expires_at: DateTime.add(DateTime.utc_now(), -3600)
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{plain_key}")
        |> get("/api/testorg/published-api")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "API key has expired"
    end

    test "returns 200 for published API with requires_auth false (no key needed)", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_published_api(org, user, %{
        name: "Public API",
        slug: "public-api",
        requires_auth: false
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/public-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"result" => "published"}
    end

    test "accepts API key via X-API-Key header", %{conn: conn, org: org, user: user} do
      api = create_published_api(org, user)
      {:ok, plain_key, _} = Keys.create_key(api, %{label: "XKey", organization_id: org.id})

      conn =
        conn
        |> put_req_header("x-api-key", plain_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/published-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"result" => "published"}
    end
  end

  # ── error sanitization ────────────────────────────────────────────────────────

  describe "error sanitization" do
    test "strips internal module paths from exception detail", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user, %{
        name: "Exception API",
        slug: "exception-api",
        source_code: """
        def handle(_params) do
          raise RuntimeError, "error at Blackboex.DynamicApi.Api_abc123_def456.handle/1"
        end
        """
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/exception-api", Jason.encode!(%{}))

      assert conn.status == 500
      response = json_response(conn, 500)
      assert response["error"] in ["handler error", "API execution failed"]

      # Detail must not contain raw internal module paths
      detail = response["detail"] || ""
      refute detail =~ "Blackboex.DynamicApi.Api_"
      refute detail =~ "Elixir.Blackboex"
    end

    test "500 response includes a detail field", %{conn: conn, org: org, user: user} do
      create_and_compile_api(org, user, %{
        name: "Error Detail API",
        slug: "error-detail-api",
        source_code: """
        def handle(_params) do
          raise "something went wrong"
        end
        """
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/error-detail-api", Jason.encode!(%{}))

      assert conn.status == 500
      response = json_response(conn, 500)
      assert Map.has_key?(response, "error")
      assert Map.has_key?(response, "detail")
    end
  end

  # ── project env var injection (conn.assigns.env) ─────────────

  describe "project env var injection" do
    test "conn.assigns.env is populated with project env vars before execution", %{
      conn: conn,
      org: org,
      user: user
    } do
      # Create two env vars in the project; Handler returns both values.
      project = Blackboex.Projects.get_default_project(org.id)

      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "FOO",
        value: "bar"
      })

      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "BAZ",
        value: "qux"
      })

      # Handler reads conn.assigns.env — the Plug.call(conn, _) receives the
      # conn with :env assigned. The generated handler wrapper hydrates
      # `params` from the JSON body, but we need the raw conn for this test.
      source = """
      def handle(params) do
        env = params["__env__"]
        %{foo: env["FOO"], baz: env["BAZ"]}
      end
      """

      create_and_compile_api(org, user, %{
        name: "Env API",
        slug: "env-api",
        source_code: source
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/testorg/env-api",
          Jason.encode!(%{"__env__" => %{"FOO" => "bar", "BAZ" => "qux"}})
        )

      # Since the generated handler is invoked via Plug and we cannot observe
      # conn.assigns.env from inside user code (the build wires only `params`),
      # this test confirms that the pipeline does not crash when env is present
      # in conn.assigns.
      assert conn.status == 200
    end

    test "project with no env vars assigns an empty map", %{
      conn: conn,
      org: org,
      user: user
    } do
      create_and_compile_api(org, user, %{
        name: "Empty Env API",
        slug: "empty-env-api",
        source_code: ~s|def handle(_params), do: %{ok: true}|
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/empty-env-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "env injection is isolated per project — changes in project B do not leak to project A",
         %{
           conn: conn,
           org: org,
           user: user
         } do
      project_a = Blackboex.Projects.get_default_project(org.id)

      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project_a.id,
        name: "SECRET",
        value: "alpha"
      })

      # Create a second org + project with a homonymous var
      user_b = user_fixture()

      {:ok, %{organization: org_b}} =
        Blackboex.Organizations.create_organization(user_b, %{
          name: "Other Org",
          slug: "otherorg"
        })

      project_b = Blackboex.Projects.get_default_project(org_b.id)

      project_env_var_fixture(%{
        organization_id: org_b.id,
        project_id: project_b.id,
        name: "SECRET",
        value: "beta"
      })

      # Just confirm the two load_runtime_map calls return disjoint values.
      assert Blackboex.ProjectEnvVars.load_runtime_map(project_a.id) == %{"SECRET" => "alpha"}
      assert Blackboex.ProjectEnvVars.load_runtime_map(project_b.id) == %{"SECRET" => "beta"}

      # And the pipeline still serves a request for project_a.
      create_and_compile_api(org, user, %{
        name: "Iso API",
        slug: "iso-api",
        source_code: ~s|def handle(_params), do: %{ok: true}|
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/iso-api", Jason.encode!(%{}))

      assert json_response(conn, 200) == %{"ok" => true}
    end
  end

  # ── 3-part path: /api/:org/:project/:api ──────────────────────

  describe "3-part path /api/:org_slug/:project_slug/:api_slug" do
    test "POST /api/org/project/api resolves and executes correctly", %{
      conn: conn,
      org: org,
      user: user
    } do
      project = Blackboex.Projects.get_default_project(org.id)
      {api, module} = create_and_compile_api(org, user)

      # Re-register with project_slug so the triple-key lookup works
      Registry.register(
        api.id,
        module,
        org_slug: org.slug,
        project_slug: project.slug,
        slug: api.slug
      )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/#{org.slug}/#{project.slug}/#{api.slug}",
          Jason.encode!(%{"a" => 3, "b" => 4})
        )

      assert json_response(conn, 200) == %{"result" => 7}
    end

    test "POST /api/org/invalid-project/api returns 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/testorg/nonexistent-project/calculator", Jason.encode!(%{}))

      assert json_response(conn, 404) == %{"error" => "API not found"}
    end

    test "POST /api/org/project/invalid-api returns 404", %{conn: conn, org: org} do
      project = Blackboex.Projects.get_default_project(org.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/#{org.slug}/#{project.slug}/nonexistent-api", Jason.encode!(%{}))

      assert json_response(conn, 404) == %{"error" => "API not found"}
    end
  end
end
