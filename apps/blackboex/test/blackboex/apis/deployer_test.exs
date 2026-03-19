defmodule Blackboex.Apis.DeployerTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit
  @moduletag :capture_log

  alias Blackboex.Apis
  alias Blackboex.Apis.Deployer
  alias Blackboex.Apis.Registry

  import Blackboex.AccountsFixtures

  @valid_source_code """
  def handle(params) do
    %{status: 200, body: %{result: "ok"}}
  end
  """

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Deploy Org"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Deploy API",
        status: "published",
        source_code: @valid_source_code,
        organization_id: org.id,
        user_id: user.id
      })

    Registry.clear()
    on_exit(fn -> Registry.clear() end)

    %{user: user, org: org, api: api}
  end

  describe "deploy/2" do
    test "compiles and registers a published API", %{api: api, org: org} do
      assert {:ok, _api} = Deployer.deploy(api, org)
      assert {:ok, _module, _metadata} = Registry.lookup(api.id)
    end

    test "rejects deploying a non-published API", %{org: org, user: user} do
      {:ok, draft_api} =
        Apis.create_api(%{
          name: "Draft",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:error, :not_published} = Deployer.deploy(draft_api, org)
    end

    test "fails deployment with invalid source code", %{api: api, org: org} do
      bad_api = %{api | source_code: "def handle(params do end end end"}

      assert {:error, _} = Deployer.deploy(bad_api, org)
    end
  end

  describe "rollback_deploy/3" do
    test "rolls back to a previous version", %{api: api, user: user} do
      # Create initial version
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: @valid_source_code,
          source: "manual_edit"
        })

      # Create v2
      {:ok, _v2} =
        Apis.create_version(api, %{
          code: @valid_source_code,
          source: "manual_edit"
        })

      assert {:ok, _api} = Deployer.rollback_deploy(api, 1, user.id)
    end

    test "fails when target version doesn't exist", %{api: api, user: user} do
      assert {:error, :version_not_found} = Deployer.rollback_deploy(api, 999, user.id)
    end
  end
end
