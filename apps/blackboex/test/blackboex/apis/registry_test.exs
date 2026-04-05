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
      assert {:ok, ^module, _metadata} = Registry.lookup(api_id)
    end

    test "registers with path lookup" do
      api_id = Ecto.UUID.generate()
      module = SomeModule

      assert :ok = Registry.register(api_id, module, org_slug: "testorg", slug: "my-api")
      assert {:ok, ^module, _metadata} = Registry.lookup_by_path("testorg", "my-api")
    end

    test "stores metadata from opts" do
      api_id = Ecto.UUID.generate()
      module = SomeModule

      assert :ok =
               Registry.register(api_id, module,
                 org_slug: "testorg",
                 slug: "my-api",
                 requires_auth: false,
                 visibility: "public"
               )

      assert {:ok, ^module, metadata} = Registry.lookup(api_id)
      assert metadata.requires_auth == false
      assert metadata.visibility == "public"
      assert metadata.api_id == api_id
    end
  end

  describe "lookup/1" do
    test "returns {:ok, module, metadata} for registered API" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, MyModule)

      assert {:ok, MyModule, metadata} = Registry.lookup(api_id)
      assert metadata.api_id == api_id
    end

    test "returns {:error, :not_found} for unregistered API" do
      assert {:error, :not_found} = Registry.lookup(Ecto.UUID.generate())
    end
  end

  describe "lookup_by_path/2" do
    test "finds API by org_slug and slug" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, PathModule, org_slug: "acme", slug: "calculator")

      assert {:ok, PathModule, _metadata} = Registry.lookup_by_path("acme", "calculator")
    end

    test "returns {:error, :not_found} for unknown path" do
      assert {:error, :not_found} = Registry.lookup_by_path("unknown", "nonexistent")
    end
  end

  describe "unregister/1" do
    test "removes API from registry" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, UnregModule, org_slug: "org", slug: "test")

      assert :ok = Registry.unregister(api_id)
      assert {:error, :not_found} = Registry.lookup(api_id)
      assert {:error, :not_found} = Registry.lookup_by_path("org", "test")
    end

    test "unregistering non-existent API does not crash" do
      assert :ok = Registry.unregister(Ecto.UUID.generate())
    end

    test "unregistering same API twice does not crash" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, SomeModule)

      assert :ok = Registry.unregister(api_id)
      assert :ok = Registry.unregister(api_id)
    end
  end

  describe "register/3 — edge cases" do
    test "re-registering same api_id overwrites module" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, OldModule)
      Registry.register(api_id, NewModule)

      assert {:ok, NewModule, _metadata} = Registry.lookup(api_id)
    end

    test "re-registering same api_id overwrites metadata" do
      api_id = Ecto.UUID.generate()

      Registry.register(api_id, Mod, requires_auth: true, visibility: "private")
      Registry.register(api_id, Mod, requires_auth: false, visibility: "public")

      assert {:ok, Mod, metadata} = Registry.lookup(api_id)
      assert metadata.requires_auth == false
      assert metadata.visibility == "public"
    end

    test "defaults to requires_auth: true and visibility: private" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, Mod)

      assert {:ok, Mod, metadata} = Registry.lookup(api_id)
      assert metadata.requires_auth == true
      assert metadata.visibility == "private"
    end

    test "register without slug does not create path entry" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, Mod)

      # No path registered, so lookup_by_path should fail
      assert {:error, :not_found} = Registry.lookup_by_path("any", "path")
    end

    test "two APIs with different paths in same org" do
      api_a = Ecto.UUID.generate()
      api_b = Ecto.UUID.generate()

      Registry.register(api_a, ModA, org_slug: "org", slug: "api-a")
      Registry.register(api_b, ModB, org_slug: "org", slug: "api-b")

      assert {:ok, ModA, _} = Registry.lookup_by_path("org", "api-a")
      assert {:ok, ModB, _} = Registry.lookup_by_path("org", "api-b")
    end

    test "same slug in different orgs are independent" do
      api_a = Ecto.UUID.generate()
      api_b = Ecto.UUID.generate()

      Registry.register(api_a, ModA, org_slug: "org1", slug: "calc")
      Registry.register(api_b, ModB, org_slug: "org2", slug: "calc")

      assert {:ok, ModA, _} = Registry.lookup_by_path("org1", "calc")
      assert {:ok, ModB, _} = Registry.lookup_by_path("org2", "calc")
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      api_a = Ecto.UUID.generate()
      api_b = Ecto.UUID.generate()

      Registry.register(api_a, ModA, org_slug: "org", slug: "a")
      Registry.register(api_b, ModB, org_slug: "org", slug: "b")

      assert :ok = Registry.clear()

      assert {:error, :not_found} = Registry.lookup(api_a)
      assert {:error, :not_found} = Registry.lookup(api_b)
      assert {:error, :not_found} = Registry.lookup_by_path("org", "a")
      assert {:error, :not_found} = Registry.lookup_by_path("org", "b")
    end

    test "clear followed by register works" do
      api_id = Ecto.UUID.generate()
      Registry.register(api_id, Mod)
      Registry.clear()
      Registry.register(api_id, Mod)

      assert {:ok, Mod, _} = Registry.lookup(api_id)
    end
  end

  describe "shutting_down?/0" do
    test "returns false when not shutting down" do
      # Reset shutdown flag if it was set by a previous test
      :persistent_term.put(:api_registry_shutting_down, false)

      refute Registry.shutting_down?()
    end
  end

  describe "lookup edge cases" do
    test "lookup with invalid (non-UUID) key returns not_found" do
      assert {:error, :not_found} = Registry.lookup("not-a-uuid")
    end

    test "lookup_by_path with empty strings returns not_found" do
      assert {:error, :not_found} = Registry.lookup_by_path("", "")
    end
  end
end
