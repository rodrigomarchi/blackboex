defmodule Blackboex.CodeGen.ModuleBuilderTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.ModuleBuilder

  @valid_handler """
  def handle(params) do
    x = Map.get(params, "a", 0)
    y = Map.get(params, "b", 0)
    %{result: x + y}
  end
  """

  describe "build_module/3 with :computation template" do
    test "generates valid Plug module" do
      module_name = :"Blackboex.DynamicApi.Api_test_comp"

      assert {:ok, code} = ModuleBuilder.build_module(module_name, @valid_handler, :computation)
      assert is_binary(code)
      assert {:ok, _ast} = Code.string_to_quoted(code)
    end

    test "includes use Plug.Router" do
      module_name = :"Blackboex.DynamicApi.Api_test_comp2"
      {:ok, code} = ModuleBuilder.build_module(module_name, @valid_handler, :computation)
      assert code =~ "use Plug.Router"
    end

    test "includes POST / and GET / routes" do
      module_name = :"Blackboex.DynamicApi.Api_test_comp3"
      {:ok, code} = ModuleBuilder.build_module(module_name, @valid_handler, :computation)
      assert code =~ ~s(post "/")
      assert code =~ ~s(get "/")
    end

    test "uses correct module name" do
      module_name = :"Blackboex.DynamicApi.Api_abc123"
      {:ok, code} = ModuleBuilder.build_module(module_name, @valid_handler, :computation)
      assert code =~ "Blackboex.DynamicApi.Api_abc123"
    end
  end

  describe "build_module/3 with :crud template" do
    test "generates module with GET/POST/PUT/DELETE" do
      module_name = :"Blackboex.DynamicApi.Api_test_crud"

      handler = """
      def handle_list(_params), do: %{items: []}
      def handle_get(id, _params), do: %{id: id}
      def handle_create(params), do: %{created: true, data: params}
      def handle_update(id, params), do: %{id: id, updated: true, data: params}
      def handle_delete(id), do: %{id: id, deleted: true}
      """

      assert {:ok, code} = ModuleBuilder.build_module(module_name, handler, :crud)
      assert code =~ ~s(get "/")
      assert code =~ ~s(get "/:id")
      assert code =~ ~s(post "/")
      assert code =~ ~s(put "/:id")
      assert code =~ ~s(delete "/:id")
    end

    test "generates valid Elixir code" do
      module_name = :"Blackboex.DynamicApi.Api_test_crud2"

      handler = """
      def handle_list(_params), do: %{items: []}
      def handle_get(id, _params), do: %{id: id}
      def handle_create(params), do: %{created: true, data: params}
      def handle_update(id, params), do: %{id: id, updated: true, data: params}
      def handle_delete(id), do: %{id: id, deleted: true}
      """

      {:ok, code} = ModuleBuilder.build_module(module_name, handler, :crud)
      assert {:ok, _ast} = Code.string_to_quoted(code)
    end
  end

  describe "build_module/3 with :webhook template" do
    test "generates module with POST only" do
      module_name = :"Blackboex.DynamicApi.Api_test_webhook"

      handler = """
      def handle_webhook(payload) do
        %{received: true, event: Map.get(payload, "event")}
      end
      """

      assert {:ok, code} = ModuleBuilder.build_module(module_name, handler, :webhook)
      assert code =~ ~s(post "/")
      # Should not have GET for data modification
      refute code =~ ~s(get "/:id")
    end

    test "generates valid Elixir code" do
      module_name = :"Blackboex.DynamicApi.Api_test_webhook2"

      handler = """
      def handle_webhook(payload) do
        %{received: true, event: Map.get(payload, "event")}
      end
      """

      {:ok, code} = ModuleBuilder.build_module(module_name, handler, :webhook)
      assert {:ok, _ast} = Code.string_to_quoted(code)
    end
  end

  describe "build_module/3 return format" do
    test "returns {:ok, module_code_string}" do
      module_name = :"Blackboex.DynamicApi.Api_test_format"
      result = ModuleBuilder.build_module(module_name, @valid_handler, :computation)
      assert {:ok, code} = result
      assert is_binary(code)
    end
  end
end
