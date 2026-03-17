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
      username: org.slug,
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
end
