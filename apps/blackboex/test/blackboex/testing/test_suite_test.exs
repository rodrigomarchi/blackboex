defmodule Blackboex.Testing.TestSuiteTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Testing
  alias Blackboex.Testing.TestSuite

  describe "changeset/2" do
    setup do
      user = insert_user()
      org = insert_org(user)
      api = insert_api(org, user)
      %{api: api}
    end

    test "valid changeset with required fields", %{api: api} do
      attrs = %{
        api_id: api.id,
        test_code:
          "defmodule MyTest do\n  use ExUnit.Case\n  test \"it works\" do\n    assert true\n  end\nend"
      }

      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with all fields", %{api: api} do
      attrs = %{
        api_id: api.id,
        version_number: 3,
        test_code: "test code here",
        status: "passed",
        results: [
          %{"name" => "test 1", "status" => "passed", "duration_ms" => 10, "error" => nil}
        ],
        total_tests: 1,
        passed_tests: 1,
        failed_tests: 0,
        duration_ms: 42
      }

      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert changeset.valid?
    end

    test "invalid without api_id" do
      changeset = TestSuite.changeset(%TestSuite{}, %{test_code: "some code"})
      assert %{api_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without test_code", %{api: api} do
      changeset = TestSuite.changeset(%TestSuite{}, %{api_id: api.id})
      assert %{test_code: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid status value", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", status: "invalid_status"}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "all valid statuses accepted", %{api: api} do
      for status <- ~w(pending running passed failed error) do
        attrs = %{api_id: api.id, test_code: "code", status: status}
        changeset = TestSuite.changeset(%TestSuite{}, attrs)
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "negative total_tests rejected", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", total_tests: -1}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{total_tests: [_]} = errors_on(changeset)
    end

    test "negative passed_tests rejected", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", passed_tests: -1}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{passed_tests: [_]} = errors_on(changeset)
    end

    test "negative failed_tests rejected", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", failed_tests: -5}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{failed_tests: [_]} = errors_on(changeset)
    end

    test "negative version_number rejected", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", version_number: -1}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{version_number: [_]} = errors_on(changeset)
    end

    test "negative duration_ms rejected", %{api: api} do
      attrs = %{api_id: api.id, test_code: "code", duration_ms: -100}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{duration_ms: [_]} = errors_on(changeset)
    end

    test "test_code max length enforced", %{api: api} do
      long_code = String.duplicate("x", 1_048_577)
      attrs = %{api_id: api.id, test_code: long_code}
      changeset = TestSuite.changeset(%TestSuite{}, attrs)
      assert %{test_code: [_]} = errors_on(changeset)
    end

    test "defaults are applied" do
      _changeset = TestSuite.changeset(%TestSuite{}, %{})
      # Check schema defaults, not changeset (defaults come from schema)
      suite = %TestSuite{}
      assert suite.status == "pending"
      assert suite.total_tests == 0
      assert suite.passed_tests == 0
      assert suite.failed_tests == 0
      assert suite.duration_ms == 0
      assert suite.results == []
    end
  end

  describe "persistence" do
    setup do
      user = insert_user()
      org = insert_org(user)
      api = insert_api(org, user)
      %{api: api, user: user, org: org}
    end

    test "insert and retrieve", %{api: api} do
      {:ok, suite} =
        %TestSuite{}
        |> TestSuite.changeset(%{api_id: api.id, test_code: "test code"})
        |> Repo.insert()

      assert suite.id
      assert suite.api_id == api.id
      assert suite.status == "pending"

      retrieved = Repo.get(TestSuite, suite.id)
      assert retrieved.test_code == "test code"
    end

    test "cascade delete when API is deleted", %{api: api} do
      {:ok, suite} =
        %TestSuite{}
        |> TestSuite.changeset(%{api_id: api.id, test_code: "test code"})
        |> Repo.insert()

      Repo.delete!(api)
      assert Repo.get(TestSuite, suite.id) == nil
    end

    test "belongs_to api association", %{api: api} do
      {:ok, suite} =
        %TestSuite{}
        |> TestSuite.changeset(%{api_id: api.id, test_code: "test code"})
        |> Repo.insert()

      suite = Repo.preload(suite, :api)
      assert suite.api.id == api.id
    end
  end

  describe "Testing context CRUD" do
    setup do
      user = insert_user()
      org = insert_org(user)
      api = insert_api(org, user)
      %{api: api, user: user, org: org}
    end

    test "create_test_suite/1", %{api: api} do
      assert {:ok, suite} =
               Testing.create_test_suite(%{api_id: api.id, test_code: "test code"})

      assert suite.api_id == api.id
      assert suite.status == "pending"
    end

    test "update_test_suite/2", %{api: api} do
      {:ok, suite} = Testing.create_test_suite(%{api_id: api.id, test_code: "code"})

      assert {:ok, updated} =
               Testing.update_test_suite(suite, %{
                 status: "passed",
                 total_tests: 5,
                 passed_tests: 5,
                 duration_ms: 120
               })

      assert updated.status == "passed"
      assert updated.total_tests == 5
    end

    test "list_test_suites/2 returns all suites for api", %{api: api} do
      {:ok, _s1} = Testing.create_test_suite(%{api_id: api.id, test_code: "code 1"})
      {:ok, _s2} = Testing.create_test_suite(%{api_id: api.id, test_code: "code 2"})
      {:ok, _s3} = Testing.create_test_suite(%{api_id: api.id, test_code: "code 3"})

      suites = Testing.list_test_suites(api.id)
      assert length(suites) == 3
    end

    test "list_test_suites/2 respects limit", %{api: api} do
      for i <- 1..5 do
        Testing.create_test_suite(%{api_id: api.id, test_code: "code #{i}"})
      end

      assert length(Testing.list_test_suites(api.id, 3)) == 3
    end

    test "get_test_suite/1", %{api: api} do
      {:ok, suite} = Testing.create_test_suite(%{api_id: api.id, test_code: "code"})
      assert {:ok, found} = Testing.get_test_suite(suite.id)
      assert found.id == suite.id
    end

    test "get_test_suite/1 not found" do
      assert {:error, :not_found} = Testing.get_test_suite(Ecto.UUID.generate())
    end

    test "get_latest_test_suite/1 returns a suite", %{api: api} do
      {:ok, _s1} = Testing.create_test_suite(%{api_id: api.id, test_code: "old"})
      {:ok, _s2} = Testing.create_test_suite(%{api_id: api.id, test_code: "latest"})

      latest = Testing.get_latest_test_suite(api.id)
      assert latest != nil
      assert latest.api_id == api.id
    end

    test "get_latest_test_suite/1 returns nil when none", %{api: _api} do
      assert Testing.get_latest_test_suite(Ecto.UUID.generate()) == nil
    end
  end

  defp insert_user do
    Blackboex.AccountsFixtures.user_fixture()
  end

  defp insert_org(user) do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Test Org #{System.unique_integer([:positive])}",
        slug: "testorg-#{System.unique_integer([:positive])}"
      })

    org
  end

  defp insert_api(org, user) do
    {:ok, api} =
      Blackboex.Apis.create_api(%{
        name: "Test API #{System.unique_integer([:positive])}",
        slug: "test-api-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    api
  end
end
