defmodule Blackboex.ApisTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.GenerationResult

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org"})

    %{user: user, org: org}
  end

  describe "create_api/2" do
    test "creates API in draft status", %{user: user, org: org} do
      attrs = %{
        name: "My API",
        description: "A test API",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      }

      assert {:ok, %Api{} = api} = Apis.create_api(attrs)
      assert api.name == "My API"
      assert api.status == "draft"
      assert api.slug == "my-api"
      assert api.organization_id == org.id
      assert api.user_id == user.id
    end

    test "returns error with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Apis.create_api(%{})
    end
  end

  describe "list_apis/1" do
    test "returns APIs for the given org", %{user: user, org: org} do
      {:ok, _api} =
        Apis.create_api(%{
          name: "API 1",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      apis = Apis.list_apis(org.id)
      assert length(apis) == 1
      assert hd(apis).name == "API 1"
    end

    test "does not return APIs from other orgs", %{org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org"})

      {:ok, _api} =
        Apis.create_api(%{
          name: "Other API",
          template_type: "computation",
          organization_id: other_org.id,
          user_id: other_user.id
        })

      apis = Apis.list_apis(org.id)
      assert apis == []
    end
  end

  describe "get_api/2" do
    test "returns API by id within org", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "My API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      assert %Api{} = Apis.get_api(org.id, api.id)
    end

    test "returns nil for non-existent API", %{org: org} do
      assert Apis.get_api(org.id, Ecto.UUID.generate()) == nil
    end

    test "returns nil for API in different org", %{org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org"})

      {:ok, api} =
        Apis.create_api(%{
          name: "Other API",
          template_type: "computation",
          organization_id: other_org.id,
          user_id: other_user.id
        })

      assert Apis.get_api(org.id, api.id) == nil
    end
  end

  describe "update_api/2" do
    test "updates API fields", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "My API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:ok, updated} = Apis.update_api(api, %{name: "Updated API"})
      assert updated.name == "Updated API"
    end
  end

  describe "publishing fields" do
    test "defaults visibility to private and requires_auth to true", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "My API",
          organization_id: org.id,
          user_id: user.id
        })

      assert api.visibility == "private"
      assert api.requires_auth == true
    end

    test "accepts visibility and requires_auth in changeset", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Public API",
          organization_id: org.id,
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
                 user_id: user.id,
                 visibility: "unlisted"
               })

      assert errors_on(changeset).visibility
    end
  end

  describe "publish/2" do
    @tag :capture_log
    test "publishes a compiled API and generates key", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Compiled API",
          status: "compiled",
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:ok, published, plain_key} = Apis.publish(api, org)
      assert published.status == "published"
      assert String.starts_with?(plain_key, "bb_live_")
    end

    @tag :capture_log
    test "rejects publishing a draft API", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Draft API",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:error, :not_compiled} = Apis.publish(api, org)
    end

    @tag :capture_log
    test "rejects publishing an already published API", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Published API",
          status: "published",
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:error, :not_compiled} = Apis.publish(api, org)
    end

    @tag :capture_log
    test "rejects publishing API with wrong organization", %{user: user, org: org} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org"})

      {:ok, api} =
        Apis.create_api(%{
          name: "Wrong Org API",
          status: "compiled",
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      # Attempting to publish with wrong org should fail
      assert {:error, :org_mismatch} = Apis.publish(api, other_org)
    end

    @tag :capture_log
    test "publish then unpublish cycle works", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Cycle API",
          status: "compiled",
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:ok, published, _key} = Apis.publish(api, org)
      assert published.status == "published"

      assert {:ok, unpublished} = Apis.unpublish(published)
      assert unpublished.status == "compiled"

      # Should not be able to unpublish again
      assert {:error, :not_published} = Apis.unpublish(unpublished)
    end
  end

  describe "unpublish/1" do
    @tag :capture_log
    test "unpublishes a published API", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Published API",
          status: "published",
          source_code: "def handle(params), do: %{ok: true}",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:ok, unpublished} = Apis.unpublish(api)
      assert unpublished.status == "compiled"
    end

    @tag :capture_log
    test "rejects unpublishing a non-published API", %{user: user, org: org} do
      {:ok, api} =
        Apis.create_api(%{
          name: "Draft API",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:error, :not_published} = Apis.unpublish(api)
    end
  end

  describe "create_api_from_generation/3" do
    test "creates Api from GenerationResult", %{user: user, org: org} do
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
               Apis.create_api_from_generation(result, org.id, user.id, "simple-api")

      assert api.source_code == result.code
      assert api.template_type == "computation"
      assert api.description == "A simple API"
      assert api.method == "POST"
      assert api.status == "draft"
      assert api.example_request == %{"key" => "value"}
      assert api.example_response == %{"ok" => true}
      assert api.param_schema == %{"type" => "object"}
    end
  end
end
