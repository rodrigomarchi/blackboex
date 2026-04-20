defmodule Blackboex.ApisTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiVersion
  alias Blackboex.CodeGen.GenerationResult

  setup :create_user_and_org

  # ---------------------------------------------------------------------------
  # create_api/1
  # ---------------------------------------------------------------------------

  describe "create_api/1 ownership" do
    test "rejects cross-org project (T6 IDOR)", %{user: user, org: org_a} do
      org_b = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
      project_b = Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org_b})

      assert {:error, :forbidden} =
               Apis.create_api(%{
                 name: "Hack",
                 organization_id: org_a.id,
                 project_id: project_b.id,
                 user_id: user.id
               })
    end
  end

  describe "create_api/1" do
    test "creates API in draft status", %{user: user, org: org} do
      attrs = %{
        name: "My API",
        description: "A test API",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, %Api{} = api} = Apis.create_api(attrs)
      assert api.name == "My API"
      assert api.status == "draft"
      assert api.slug =~ ~r/^my-api-[a-z0-9]{6}$/
      assert api.organization_id == org.id
      assert api.user_id == user.id
    end

    test "returns error with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Apis.create_api(%{})
    end

    test "rejects invalid template_type", %{user: user, org: org} do
      assert {:error, changeset} =
               Apis.create_api(%{
                 name: "Bad Template",
                 template_type: "invalid",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id
               })

      assert errors_on(changeset).template_type
    end

    test "rejects invalid method", %{user: user, org: org} do
      assert {:error, changeset} =
               Apis.create_api(%{
                 name: "Bad Method",
                 method: "SEARCH",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id
               })

      assert errors_on(changeset).method
    end

    test "rejects invalid status", %{user: user, org: org} do
      assert {:error, changeset} =
               Apis.create_api(%{
                 name: "Bad Status",
                 status: "pending",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id
               })

      assert errors_on(changeset).status
    end

    test "slug is generated from name", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Hello World API",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      assert api.slug =~ ~r/^hello-world-api-[a-z0-9]{6}$/
    end
  end

  # ---------------------------------------------------------------------------
  # list_apis/1
  # ---------------------------------------------------------------------------

  describe "list_apis/1" do
    test "returns APIs for the given org", %{user: user, org: org} do
      api_fixture(%{user: user, org: org})
      apis = Apis.list_apis(org.id)
      assert length(apis) == 1
    end

    test "returns multiple APIs ordered by newest first", %{user: user, org: org} do
      _a1 = api_fixture(%{user: user, org: org})
      _a2 = api_fixture(%{user: user, org: org})
      apis = Apis.list_apis(org.id)
      assert length(apis) == 2
    end

    test "does not return APIs from other orgs", %{org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org #{System.unique_integer([:positive])}"
        })

      api_fixture(%{user: other_user, org: other_org})

      assert Apis.list_apis(org.id) == []
    end

    test "returns empty list for org with no APIs", %{org: org} do
      assert Apis.list_apis(org.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # get_api/2
  # ---------------------------------------------------------------------------

  describe "get_api/2" do
    test "returns API by id within org", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert %Api{id: id} = Apis.get_api(org.id, api.id)
      assert id == api.id
    end

    test "returns nil for non-existent API", %{org: org} do
      assert Apis.get_api(org.id, Ecto.UUID.generate()) == nil
    end

    test "returns nil for API in different org", %{org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org #{System.unique_integer([:positive])}"
        })

      api = api_fixture(%{user: other_user, org: other_org})

      assert Apis.get_api(org.id, api.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # update_api/2
  # ---------------------------------------------------------------------------

  describe "update_api/2" do
    test "updates API fields", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:ok, updated} = Apis.update_api(api, %{name: "Updated API"})
      assert updated.name == "Updated API"
    end

    test "returns error for invalid update", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:error, %Ecto.Changeset{}} = Apis.update_api(api, %{name: ""})
    end

    test "updates status to compiled", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:ok, updated} = Apis.update_api(api, %{status: "compiled"})
      assert updated.status == "compiled"
    end

    test "updates api name after file upsert", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, updated} = Apis.update_api(api, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  # ---------------------------------------------------------------------------
  # delete_api/1
  # ---------------------------------------------------------------------------

  describe "delete_api/1" do
    test "deletes a draft API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:ok, %Api{}} = Apis.delete_api(api)
      assert Apis.get_api(org.id, api.id) == nil
    end

    @tag :capture_log
    test "deletes a compiled API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, %Api{}} = Apis.delete_api(api)
      assert Apis.get_api(org.id, api.id) == nil
    end

    @tag :capture_log
    test "deletes a published API (unregisters from registry)", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "published"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, %Api{}} = Apis.delete_api(api)
      assert Apis.get_api(org.id, api.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # publishing fields
  # ---------------------------------------------------------------------------

  describe "publishing fields" do
    test "defaults visibility to private and requires_auth to false", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "My API",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      assert api.visibility == "private"
      assert api.requires_auth == false
    end

    test "accepts visibility and requires_auth in changeset", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Public API",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id,
          visibility: "public",
          requires_auth: false
        })

      assert api.visibility == "public"
      assert api.requires_auth == false
    end

    test "rejects invalid visibility", %{user: user, org: org} do
      assert {:error, changeset} =
               Apis.create_api(%{
                 name: "Bad API",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id,
                 visibility: "unlisted"
               })

      assert errors_on(changeset).visibility
    end
  end

  # ---------------------------------------------------------------------------
  # publish/2
  # ---------------------------------------------------------------------------

  describe "publish/2" do
    @tag :capture_log
    test "publishes a compiled API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, published} = Apis.publish(api, org)
      assert published.status == "published"
    end

    @tag :capture_log
    test "rejects publishing a draft API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:error, :not_compiled} = Apis.publish(api, org)
    end

    @tag :capture_log
    test "rejects publishing an already published API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "published"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:error, :not_compiled} = Apis.publish(api, org)
    end

    @tag :capture_log
    test "rejects publishing API with wrong organization", %{user: user, org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{
          name: "Other Org #{System.unique_integer([:positive])}"
        })

      api = api_fixture(%{user: user, org: org, status: "compiled"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:error, :org_mismatch} = Apis.publish(api, other_org)
    end

    @tag :capture_log
    test "publish then unpublish cycle works", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, published} = Apis.publish(api, org)
      assert published.status == "published"

      assert {:ok, unpublished} = Apis.unpublish(published)
      assert unpublished.status == "compiled"

      assert {:error, :not_published} = Apis.unpublish(unpublished)
    end
  end

  # ---------------------------------------------------------------------------
  # unpublish/1
  # ---------------------------------------------------------------------------

  describe "unpublish/1" do
    @tag :capture_log
    test "unpublishes a published API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "published"})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, unpublished} = Apis.unpublish(api)
      assert unpublished.status == "compiled"
    end

    @tag :capture_log
    test "rejects unpublishing a non-published API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:error, :not_published} = Apis.unpublish(api)
    end

    @tag :capture_log
    test "rejects unpublishing a compiled (non-published) API", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})
      assert {:error, :not_published} = Apis.unpublish(api)
    end
  end

  # ---------------------------------------------------------------------------
  # create_version/2
  # ---------------------------------------------------------------------------

  describe "create_version/2" do
    test "creates first version with version_number 1", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      assert {:ok, %ApiVersion{} = v} =
               Apis.create_version(api, %{
                 source: "manual_edit"
               })

      assert v.version_number == 1
      assert v.source == "manual_edit"
      assert v.api_id == api.id
    end

    test "increments version_number on subsequent saves", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      {:ok, v1} = Apis.create_version(api, %{source: "manual_edit"})

      # reload api
      api = Apis.get_api(org.id, api.id)

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: %{ok: true}", file_type: "source"}
      ])

      {:ok, v2} = Apis.create_version(api, %{source: "generation"})

      assert v1.version_number == 1
      assert v2.version_number == 2
    end

    test "second version has a diff_summary", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "old code", file_type: "source"}
      ])

      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})
      api = Apis.get_api(org.id, api.id)

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "new code completely different", file_type: "source"}
      ])

      {:ok, v2} = Apis.create_version(api, %{source: "generation"})

      assert v2.diff_summary != nil
    end

    test "first version has nil diff_summary (no prior version)", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      {:ok, v1} = Apis.create_version(api, %{source: "manual_edit"})

      assert v1.diff_summary == nil
    end

    test "stores file snapshots in version", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: p", file_type: "source"}
      ])

      {:ok, v} = Apis.create_version(api, %{source: "manual_edit"})

      assert is_list(v.file_snapshots)
    end

    test "file snapshots capture current file content", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "def handle(p), do: :updated", file_type: "source"}
      ])

      {:ok, _v} = Apis.create_version(api, %{source: "manual_edit"})

      file = Apis.get_file(api.id, "/src/handler.ex")
      assert file.content == "def handle(p), do: :updated"
    end

    test "returns error for missing required fields", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:error, _} = Apis.create_version(api, %{})
    end

    test "returns error for invalid source", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      assert {:error, _} =
               Apis.create_version(api, %{source: "invalid_src"})
    end
  end

  # ---------------------------------------------------------------------------
  # list_versions/1
  # ---------------------------------------------------------------------------

  describe "list_versions/1" do
    test "returns empty list when no versions", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert Apis.list_versions(api.id) == []
    end

    test "returns versions in descending order", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v1", file_type: "source"}])
      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})
      api = Apis.get_api(org.id, api.id)
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v2", file_type: "source"}])
      {:ok, _v2} = Apis.create_version(api, %{source: "generation"})

      versions = Apis.list_versions(api.id)
      assert length(versions) == 2
      [first | _] = versions
      assert first.version_number == 2
    end
  end

  # ---------------------------------------------------------------------------
  # get_version/2
  # ---------------------------------------------------------------------------

  describe "get_version/2" do
    test "returns version by api_id and version_number", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v1 code", file_type: "source"}])

      {:ok, v1} = Apis.create_version(api, %{source: "manual_edit"})

      assert %ApiVersion{version_number: 1} = Apis.get_version(api.id, 1)
      assert v1.id == Apis.get_version(api.id, 1).id
    end

    test "returns nil for non-existent version", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert Apis.get_version(api.id, 99) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # get_latest_version/1
  # ---------------------------------------------------------------------------

  describe "get_latest_version/1" do
    test "returns nil when no versions exist", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert Apis.get_latest_version(api) == nil
    end

    test "returns the version with the highest number", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v1", file_type: "source"}])
      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})
      api = Apis.get_api(org.id, api.id)
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v2", file_type: "source"}])
      {:ok, v2} = Apis.create_version(api, %{source: "generation"})

      latest = Apis.get_latest_version(api)
      assert latest.id == v2.id
      assert latest.version_number == 2
    end
  end

  # ---------------------------------------------------------------------------
  # rollback_to_version/3
  # ---------------------------------------------------------------------------

  describe "rollback_to_version/3" do
    test "creates a new version as rollback", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "original code", file_type: "source"}
      ])

      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})
      api = Apis.get_api(org.id, api.id)

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "changed code", file_type: "source"}
      ])

      {:ok, _v2} = Apis.create_version(api, %{source: "generation"})
      api = Apis.get_api(org.id, api.id)

      assert {:ok, %ApiVersion{} = rollback_v} = Apis.rollback_to_version(api, 1)
      assert rollback_v.version_number == 3
      assert rollback_v.source == "rollback"
    end

    test "returns error when target version does not exist", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert {:error, :version_not_found} = Apis.rollback_to_version(api, 99)
    end

    test "rollback with user id sets created_by_id", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})

      Apis.upsert_files(api, [
        %{path: "/src/handler.ex", content: "original", file_type: "source"}
      ])

      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})
      api = Apis.get_api(org.id, api.id)

      assert {:ok, %ApiVersion{} = rollback_v} =
               Apis.rollback_to_version(api, 1, user.id)

      assert rollback_v.created_by_id == user.id
    end
  end

  # ---------------------------------------------------------------------------
  # create_api_from_generation/5
  # ---------------------------------------------------------------------------

  describe "create_api_from_generation/5" do
    test "creates Api from GenerationResult", %{user: user, org: org, project: project} do
      result = %GenerationResult{
        code: "def call(conn, params), do: json(conn, %{ok: true})",
        template: :computation,
        description: "A simple API",
        provider: "anthropic",
        model: "anthropic:claude-sonnet-4-20250514",
        tokens_used: 300,
        duration_ms: 1500,
        method: "POST",
        example_request: %{"key" => "value"},
        example_response: %{"ok" => true},
        param_schema: %{"type" => "object"}
      }

      assert {:ok, %Api{} = api} =
               Apis.create_api_from_generation(result, org.id, user.id, "simple-api", project.id)

      assert api.template_type == "computation"
      assert api.description == "A simple API"
      assert api.method == "POST"
      assert api.status == "draft"
      assert api.example_request == %{"key" => "value"}
      assert api.example_response == %{"ok" => true}
      assert api.param_schema == %{"type" => "object"}
    end

    test "method defaults to POST when nil in result", %{user: user, org: org, project: project} do
      result = %GenerationResult{
        code: "def handle(p), do: p",
        template: :computation,
        description: "No method",
        provider: "anthropic",
        model: "anthropic:claude-sonnet-4-20250514",
        tokens_used: 100,
        duration_ms: 500,
        method: nil,
        example_request: nil,
        example_response: nil,
        param_schema: nil
      }

      assert {:ok, api} =
               Apis.create_api_from_generation(result, org.id, user.id, "no-method", project.id)

      assert api.method == "POST"
    end
  end

  # ---------------------------------------------------------------------------
  # create_api_from_template/2
  # ---------------------------------------------------------------------------

  describe "create_api_from_template/2" do
    test "creates API with status compiled", %{user: user, org: org} do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")
      assert api.status == "compiled"
    end

    test "saves template_id on the API", %{user: user, org: org} do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")
      assert api.template_id == "cotacao-frete"
    end

    test "generation_status is nil (no LLM pipeline triggered)", %{user: user, org: org} do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")
      assert api.generation_status == nil
    end

    test "creates 6 files with template content", %{user: user, org: org} do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")

      files = Apis.list_files(api.id)
      paths = Enum.map(files, & &1.path) |> MapSet.new()

      assert MapSet.member?(paths, "/src/handler.ex")
      assert MapSet.member?(paths, "/src/helpers.ex")
      assert MapSet.member?(paths, "/src/request_schema.ex")
      assert MapSet.member?(paths, "/src/response_schema.ex")
      assert MapSet.member?(paths, "/test/handler_test.ex")
      assert MapSet.member?(paths, "/README.md")
      assert length(files) == 6
    end

    test "fills param_schema, example_request, example_response, validation_report", %{
      user: user,
      org: org
    } do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")

      assert is_map(api.param_schema) and map_size(api.param_schema) > 0
      assert is_map(api.example_request) and map_size(api.example_request) > 0
      assert is_map(api.example_response) and map_size(api.example_response) > 0
      assert is_map(api.validation_report) and api.validation_report["overall"] == "pass"
    end

    test "sets method from template", %{user: user, org: org} do
      attrs = %{
        name: "Frete API",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, api} = Apis.create_api_from_template(attrs, "cotacao-frete")
      assert api.method == "POST"
    end

    test "returns error for unknown template", %{user: user, org: org} do
      attrs = %{
        name: "Unknown",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:error, :template_not_found} =
               Apis.create_api_from_template(attrs, "does-not-exist")
    end

    test "returns changeset error for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Apis.create_api_from_template(%{}, "cotacao-frete")
    end
  end

  # ---------------------------------------------------------------------------
  # published_version/1
  # ---------------------------------------------------------------------------

  describe "published_version/1" do
    test "returns nil when api has no published version", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      assert Apis.published_version(api.id) == nil
    end

    test "returns nil when api has versions but none with source publish", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org})
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "code", file_type: "source"}])
      {:ok, _v1} = Apis.create_version(api, %{source: "manual_edit"})

      assert Apis.published_version(api.id) == nil
    end

    test "returns the latest publish version", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "code", file_type: "source"}])

      {:ok, published_api} = Apis.publish(api, org)

      version = Apis.published_version(published_api.id)
      assert %ApiVersion{} = version
      assert version.source == "publish"
      assert version.version_label != nil
    end

    test "returns latest publish version when multiple publishes exist", %{user: user, org: org} do
      api = api_fixture(%{user: user, org: org, status: "compiled"})
      Apis.upsert_files(api, [%{path: "/src/handler.ex", content: "v1", file_type: "source"}])

      {:ok, published_api} = Apis.publish(api, org)

      # Unpublish, edit, republish
      {:ok, unpublished} = Apis.unpublish(published_api)
      recompiled = %{unpublished | status: "compiled"}
      {:ok, _} = Apis.update_api(recompiled, %{status: "compiled"})
      api_reloaded = Apis.get_api(org.id, api.id)
      {:ok, _} = Apis.update_api(api_reloaded, %{status: "compiled"})
      api_compiled = Apis.get_api(org.id, api.id)
      {:ok, republished} = Apis.publish(api_compiled, org)

      version = Apis.published_version(republished.id)
      assert %ApiVersion{} = version
      assert version.source == "publish"

      # Should be the second publish version (higher version_number)
      all_publish_versions =
        Apis.list_versions(api.id)
        |> Enum.filter(&(&1.source == "publish"))

      assert length(all_publish_versions) == 2

      assert version.version_number ==
               Enum.max_by(all_publish_versions, & &1.version_number).version_number
    end
  end

  describe "list_for_project/2" do
    test "returns only apis belonging to the given project", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Project A"})
      project_b = project_fixture(%{user: user, org: org, name: "Project B"})

      _a1 = api_fixture(%{user: user, org: org, project: project_a, name: "Alpha API"})
      _a2 = api_fixture(%{user: user, org: org, project: project_a, name: "Beta API"})
      _a3 = api_fixture(%{user: user, org: org, project: project_a, name: "Gamma API"})
      _b1 = api_fixture(%{user: user, org: org, project: project_b, name: "Delta API"})
      _b2 = api_fixture(%{user: user, org: org, project: project_b, name: "Epsilon API"})

      results_a = Apis.list_for_project(project_a.id)
      results_b = Apis.list_for_project(project_b.id)

      assert length(results_a) == 3
      assert length(results_b) == 2
      assert Enum.all?(results_a, &(&1.project_id == project_a.id))
    end

    test "returns apis ordered by name ASC", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Sorted Project"})

      api_fixture(%{user: user, org: org, project: project, name: "Zeta"})
      api_fixture(%{user: user, org: org, project: project, name: "Alpha"})
      api_fixture(%{user: user, org: org, project: project, name: "Mango"})

      results = Apis.list_for_project(project.id)
      names = Enum.map(results, & &1.name)

      assert names == Enum.sort(names)
    end

    test "respects :limit option", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Limited Project"})

      api_fixture(%{user: user, org: org, project: project, name: "API One"})
      api_fixture(%{user: user, org: org, project: project, name: "API Two"})
      api_fixture(%{user: user, org: org, project: project, name: "API Three"})

      results = Apis.list_for_project(project.id, limit: 2)

      assert length(results) == 2
    end
  end

  describe "move_api/2" do
    test "moves api to another project in same org", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      project_b = project_fixture(%{user: user, org: org, name: "Dest"})
      api = api_fixture(%{user: user, org: org, project: project_a})

      assert {:ok, updated} = Apis.move_api(api, project_b.id)
      assert updated.project_id == project_b.id
    end

    test "returns forbidden when destination project belongs to another org", %{
      user: user,
      org: org
    } do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      api = api_fixture(%{user: user, org: org, project: project_a})

      {other_user, other_org} = user_and_org_fixture()
      other_project = project_fixture(%{user: other_user, org: other_org})

      assert {:error, :forbidden} = Apis.move_api(api, other_project.id)
      assert Apis.get_api(org.id, api.id).project_id == project_a.id
    end

    test "returns forbidden when destination project_id does not exist", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      api = api_fixture(%{user: user, org: org, project: project_a})
      nonexistent_id = Ecto.UUID.generate()

      assert {:error, :forbidden} = Apis.move_api(api, nonexistent_id)
      assert Apis.get_api(org.id, api.id).project_id == project_a.id
    end
  end
end
