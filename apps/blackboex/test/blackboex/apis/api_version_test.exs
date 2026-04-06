defmodule Blackboex.Apis.ApiVersionTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.ApiVersion

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{api: api, user: user, org: org}
  end

  describe "create_version/2" do
    test "creates first version with number 1", %{api: api, user: user} do
      assert {:ok, %ApiVersion{} = version} =
               Apis.create_version(api, %{
                 code: "def handle(params), do: %{ok: true}",
                 source: "manual_edit",
                 created_by_id: user.id
               })

      assert version.version_number == 1
      assert version.source == "manual_edit"
      assert version.code =~ "ok: true"
    end

    test "auto-increments version number", %{api: api, user: user} do
      {:ok, v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      # Reload api to get updated source_code
      api = Apis.get_api(api.organization_id, api.id)

      {:ok, v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      assert v1.version_number == 1
      assert v2.version_number == 2
    end

    test "updates api.source_code in same transaction", %{api: api, user: user} do
      new_code = "def handle(_), do: %{updated: true}"

      {:ok, _version} =
        Apis.create_version(api, %{
          code: new_code,
          source: "manual_edit",
          created_by_id: user.id
        })

      updated_api = Apis.get_api(api.organization_id, api.id)
      assert updated_api.source_code == new_code
    end

    test "computes diff_summary from previous version", %{api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "line1\nline2\nline3",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, v2} =
        Apis.create_version(api, %{
          code: "line1\nmodified\nline3\nline4",
          source: "manual_edit",
          created_by_id: user.id
        })

      assert v2.diff_summary =~ "added"
    end

    test "validates source inclusion", %{api: api} do
      assert {:error, changeset} =
               Apis.create_version(api, %{
                 code: "some code",
                 source: "invalid_source"
               })

      assert %{source: [_]} = errors_on(changeset)
    end
  end

  describe "list_versions/1" do
    test "returns versions in descending order", %{api: api, user: user} do
      {:ok, _} =
        Apis.create_version(api, %{code: "v1", source: "generation", created_by_id: user.id})

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, _} =
        Apis.create_version(api, %{code: "v2", source: "manual_edit", created_by_id: user.id})

      versions = Apis.list_versions(api.id)
      assert length(versions) == 2
      assert hd(versions).version_number == 2
    end
  end

  describe "get_version/2" do
    test "returns specific version", %{api: api, user: user} do
      {:ok, _} =
        Apis.create_version(api, %{code: "v1 code", source: "generation", created_by_id: user.id})

      version = Apis.get_version(api.id, 1)
      assert version.code == "v1 code"
    end

    test "returns nil for non-existent version", %{api: api} do
      assert Apis.get_version(api.id, 999) == nil
    end
  end

  describe "get_latest_version/1" do
    test "returns most recent version", %{api: api, user: user} do
      {:ok, _} =
        Apis.create_version(api, %{code: "v1", source: "generation", created_by_id: user.id})

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, _} =
        Apis.create_version(api, %{code: "v2", source: "manual_edit", created_by_id: user.id})

      latest = Apis.get_latest_version(api)
      assert latest.version_number == 2
      assert latest.code == "v2"
    end

    test "returns nil when no versions exist", %{api: api} do
      assert Apis.get_latest_version(api) == nil
    end
  end

  describe "create_version/2 edge cases" do
    test "concurrent saves get unique version numbers", %{api: api, user: user} do
      # Simulate concurrent saves by creating quickly in sequence
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Reload api each time to get fresh data
            fresh_api = Apis.get_api(api.organization_id, api.id)

            Apis.create_version(fresh_api, %{
              code: "def handle(_), do: %{v: #{i}}",
              source: "manual_edit",
              created_by_id: user.id
            })
          end)
        end

      results = Task.await_many(tasks, 5000)
      successes = Enum.filter(results, &match?({:ok, _}, &1))

      # At least one should succeed (unique constraint handled by transaction)
      assert successes != []

      # All version numbers should be unique
      versions = Apis.list_versions(api.id)
      numbers = Enum.map(versions, & &1.version_number)
      assert numbers == Enum.uniq(numbers)
    end

    test "first version has nil diff_summary", %{api: api, user: user} do
      {:ok, v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: :ok",
          source: "generation",
          created_by_id: user.id
        })

      assert v1.diff_summary == nil
    end

    test "version with empty code is rejected", %{api: api, user: user} do
      assert {:error, _changeset} =
               Apis.create_version(api, %{
                 code: "",
                 source: "manual_edit",
                 created_by_id: user.id
               })
    end
  end

  describe "rollback_to_version/2" do
    test "creates new version with old code", %{api: api, user: user} do
      {:ok, _} =
        Apis.create_version(api, %{code: "original", source: "generation", created_by_id: user.id})

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, _} =
        Apis.create_version(api, %{
          code: "modified",
          source: "manual_edit",
          created_by_id: user.id
        })

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, rollback_version} = Apis.rollback_to_version(api, 1, user.id)

      assert rollback_version.version_number == 3
      assert rollback_version.source == "rollback"
      assert rollback_version.code == "original"
    end

    test "preserves history (does not delete versions)", %{api: api, user: user} do
      {:ok, _} =
        Apis.create_version(api, %{code: "v1", source: "generation", created_by_id: user.id})

      api = Apis.get_api(api.organization_id, api.id)

      {:ok, _} =
        Apis.create_version(api, %{code: "v2", source: "manual_edit", created_by_id: user.id})

      api = Apis.get_api(api.organization_id, api.id)
      {:ok, _} = Apis.rollback_to_version(api, 1, user.id)

      assert length(Apis.list_versions(api.id)) == 3
    end

    test "returns error for non-existent version", %{api: api} do
      assert {:error, :version_not_found} = Apis.rollback_to_version(api, 999)
    end
  end
end
