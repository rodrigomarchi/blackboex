defmodule Blackboex.Apis.RegistryTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  alias Blackboex.Apis.Registry

  # Use a unique ETS table name per test to avoid conflicts
  # Registry is started in Application supervision tree, so we test against the running instance

  setup do
    # Clean up registry between tests
    Registry.clear()
    :ok
  end

  describe "register/2" do
    test "inserts api_id -> module mapping" do
      api_id = Ecto.UUID.generate()
      module = SomeModule

      assert :ok = Registry.register(api_id, module)
      assert {:ok, ^module} = Registry.lookup(api_id)
    end

    test "registers with path lookup" do
      api_id = Ecto.UUID.generate()
      module = SomeModule

      assert :ok = Registry.register(api_id, module, username: "testorg", slug: "my-api")
      assert {:ok, ^module} = Registry.lookup_by_path("testorg", "my-api")
    end
  end

  describe "lookup/1" do
    test "returns {:ok, module} for registered API" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, MyModule)

      assert {:ok, MyModule} = Registry.lookup(api_id)
    end

    test "returns {:error, :not_found} for unregistered API" do
      assert {:error, :not_found} = Registry.lookup(Ecto.UUID.generate())
    end
  end

  describe "lookup_by_path/2" do
    test "finds API by username and slug" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, PathModule, username: "acme", slug: "calculator")

      assert {:ok, PathModule} = Registry.lookup_by_path("acme", "calculator")
    end

    test "returns {:error, :not_found} for unknown path" do
      assert {:error, :not_found} = Registry.lookup_by_path("unknown", "nonexistent")
    end
  end

  describe "unregister/1" do
    test "removes API from registry" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, UnregModule, username: "org", slug: "test")

      assert :ok = Registry.unregister(api_id)
      assert {:error, :not_found} = Registry.lookup(api_id)
      assert {:error, :not_found} = Registry.lookup_by_path("org", "test")
    end
  end
end
