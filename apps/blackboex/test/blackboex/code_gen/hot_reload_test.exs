defmodule Blackboex.CodeGen.HotReloadTest do
  use Blackboex.DataCase, async: false

  @moduletag :integration

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  setup do
    Registry.clear()
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Hot Reload Org",
        slug: "hotreload"
      })

    %{user: user, org: org}
  end

  describe "hot reload" do
    test "compiling v2 updates behavior without downtime", %{org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Hot API",
          slug: "hot-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      Apis.upsert_files(api, [
        %{
          path: "/src/handler.ex",
          content: "def handle(_params), do: %{version: 1}",
          file_type: "source"
        }
      ])

      # Compile v1
      source_v1 = Apis.get_source_for_compilation(api.id) |> Enum.map_join("\n\n", & &1.content)
      {:ok, module} = Compiler.compile(api, source_v1)
      Registry.register(api.id, module, org_slug: org.slug, slug: api.slug)

      # Verify v1 behavior
      conn =
        Plug.Test.conn(:post, "/", "{}")
        |> Plug.Conn.put_req_header("content-type", "application/json")

      result = module.call(conn, module.init([]))
      assert Jason.decode!(result.resp_body)["version"] == 1

      # Compile v2 (hot reload)
      new_code = "def handle(_params), do: %{version: 2}"
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: new_code, file_type: "source"}])
      {:ok, module2} = Compiler.compile(api, new_code)

      # Same module name
      assert module == module2

      # v2 behavior immediately available
      conn2 =
        Plug.Test.conn(:post, "/", "{}")
        |> Plug.Conn.put_req_header("content-type", "application/json")

      result2 = module2.call(conn2, module2.init([]))
      assert Jason.decode!(result2.resp_body)["version"] == 2

      on_exit(fn -> Compiler.unload(module2) end)
    end

    test "BEAM holds two versions simultaneously", %{org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Dual API",
          slug: "dual-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      Apis.upsert_files(api, [
        %{
          path: "/src/handler.ex",
          content: "def handle(_params), do: %{v: 1}",
          file_type: "source"
        }
      ])

      source_v1 = Apis.get_source_for_compilation(api.id) |> Enum.map_join("\n\n", & &1.content)
      {:ok, module} = Compiler.compile(api, source_v1)

      # Module loaded
      assert function_exported?(module, :call, 2)

      # Compile v2 — BEAM holds both
      {:ok, ^module} = Compiler.compile(api, "def handle(_params), do: %{v: 2}")

      # Still works
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "soft purge removes old version", %{org: org, user: user} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Purge API",
          slug: "purge-api",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      Apis.upsert_files(api, [
        %{
          path: "/src/handler.ex",
          content: "def handle(_params), do: %{v: 1}",
          file_type: "source"
        }
      ])

      source_v1 = Apis.get_source_for_compilation(api.id) |> Enum.map_join("\n\n", & &1.content)
      {:ok, module} = Compiler.compile(api, source_v1)
      {:ok, ^module} = Compiler.compile(api, "def handle(_params), do: %{v: 2}")

      # Soft purge succeeds (no processes running old version)
      assert :code.soft_purge(module)

      # Module still works (current version)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end
  end
end
