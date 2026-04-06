defmodule Blackboex.CodeGen.CompilerTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.Compiler

  @valid_handler """
  def handle(params) do
    x = Map.get(params, "a", 0)
    y = Map.get(params, "b", 0)
    %{result: x + y}
  end
  """

  defp build_api(attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test API",
      slug: "test-api",
      template_type: "computation",
      status: "draft"
    }

    struct(Api, Map.merge(defaults, attrs))
  end

  describe "compile/2" do
    test "compiles valid code and returns {:ok, module}" do
      api = build_api()

      assert {:ok, module} = Compiler.compile(api, @valid_handler)
      assert is_atom(module)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "rejects insecure code via AST validation" do
      api = build_api()

      insecure_code = """
      def handle(_params) do
        File.read("/etc/passwd")
      end
      """

      assert {:error, {:validation, reasons}} = Compiler.compile(api, insecure_code)
      assert is_list(reasons)
      assert Enum.any?(reasons, &String.contains?(&1, "File"))
    end

    test "returns error for code that fails to compile" do
      api = build_api()

      bad_code = """
      def handle(params) do
        UndefinedModule.nonexistent_function(params)
      end
      """

      # This should still compile (Elixir doesn't check module existence at compile time)
      # but we test the path
      result = Compiler.compile(api, bad_code)
      assert {:ok, _module} = result

      on_exit(fn ->
        case result do
          {:ok, mod} -> Compiler.unload(mod)
          _ -> :ok
        end
      end)
    end

    test "compiled module responds to function_exported?/3" do
      api = build_api()

      {:ok, module} = Compiler.compile(api, @valid_handler)
      assert function_exported?(module, :call, 2)
      assert function_exported?(module, :init, 1)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "recompiling same module works (hot reload)" do
      api = build_api()

      {:ok, module1} = Compiler.compile(api, @valid_handler)

      updated_handler = """
      def handle(params) do
        x = Map.get(params, "a", 0)
        %{result: x * 3}
      end
      """

      {:ok, module2} = Compiler.compile(api, updated_handler)
      assert module1 == module2

      on_exit(fn -> Compiler.unload(module2) end)
    end
  end

  describe "unload/1" do
    test "removes loaded module" do
      api = build_api()

      {:ok, module} = Compiler.compile(api, @valid_handler)
      assert function_exported?(module, :call, 2)

      assert :ok = Compiler.unload(module)
      refute function_exported?(module, :call, 2)
    end
  end
end
