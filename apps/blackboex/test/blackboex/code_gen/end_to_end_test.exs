defmodule Blackboex.CodeGen.EndToEndTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  setup do
    Registry.clear()
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "E2E Org", slug: "e2eorg"})

    %{user: user, org: org}
  end

  describe "generate -> compile -> register -> query" do
    test "computation API end-to-end", %{org: org, user: user} do
      # 1. Create API with valid code
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

      assert api.status == "draft"

      # 2. Compile
      {:ok, module} = Compiler.compile(api, api.source_code)
      assert function_exported?(module, :call, 2)

      # 3. Update status
      {:ok, api} = Apis.update_api(api, %{status: "compiled"})
      assert api.status == "compiled"

      # 4. Register
      :ok = Registry.register(api.id, module, org_slug: org.slug, slug: api.slug)

      # 5. Verify lookup works
      assert {:ok, ^module, _metadata} = Registry.lookup(api.id)
      assert {:ok, ^module, _metadata} = Registry.lookup_by_path("e2eorg", "calculator")

      # 6. Execute via sandbox with a conn-like test
      conn =
        Plug.Test.conn(:post, "/", Jason.encode!(%{"a" => 5, "b" => 3}))
        |> Plug.Conn.put_req_header("content-type", "application/json")

      result_conn = module.call(conn, module.init([]))
      assert result_conn.status == 200

      body = Jason.decode!(result_conn.resp_body)
      assert body["result"] == 8

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "crud API end-to-end", %{org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Todo API",
          slug: "todos",
          template_type: "crud",
          organization_id: org.id,
          user_id: user.id,
          source_code: """
          def handle_list(_params), do: %{items: ["item1", "item2"]}
          def handle_get(id, _params), do: %{id: id, name: "Item"}
          def handle_create(params), do: %{created: true, data: params}
          def handle_update(id, params), do: %{id: id, updated: true, data: params}
          def handle_delete(id), do: %{id: id, deleted: true}
          """
        })

      {:ok, module} = Compiler.compile(api, api.source_code)

      # GET /
      conn = Plug.Test.conn(:get, "/")
      result = module.call(conn, module.init([]))
      assert result.status == 200
      assert Jason.decode!(result.resp_body) == %{"items" => ["item1", "item2"]}

      # POST /
      conn =
        Plug.Test.conn(:post, "/", Jason.encode!(%{"name" => "New"}))
        |> Plug.Conn.put_req_header("content-type", "application/json")

      result = module.call(conn, module.init([]))
      assert result.status == 201

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "insecure code is rejected" do
      {:error, {:validation, reasons}} =
        Compiler.compile(
          %Blackboex.Apis.Api{
            id: Ecto.UUID.generate(),
            template_type: "computation"
          },
          """
          def handle(_params) do
            File.read("/etc/passwd")
          end
          """
        )

      assert Enum.any?(reasons, &String.contains?(&1, "File"))
    end
  end
end
