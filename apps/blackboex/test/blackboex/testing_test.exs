defmodule Blackboex.TestingTest do
  use Blackboex.DataCase, async: true

  @moduletag :integration

  alias Blackboex.Testing
  alias Blackboex.Testing.TestRequest

  setup do
    user = Blackboex.AccountsFixtures.user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Test Org #{System.unique_integer([:positive])}",
        slug: "testorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Blackboex.Apis.create_api(%{
        name: "Test API",
        slug: "test-api-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    %{user: user, org: org, api: api}
  end

  defp valid_attrs(api, user) do
    %{
      api_id: api.id,
      user_id: user.id,
      method: "GET",
      path: "/api/testorg/test-api",
      headers: %{"content-type" => "application/json"},
      response_status: 200,
      response_headers: %{"content-type" => "application/json"},
      response_body: ~s({"result": 42}),
      duration_ms: 15
    }
  end

  describe "create_test_request/1" do
    test "creates a test request with valid attrs", %{api: api, user: user} do
      assert {:ok, %TestRequest{} = tr} = Testing.create_test_request(valid_attrs(api, user))
      assert tr.method == "GET"
      assert tr.path == "/api/testorg/test-api"
      assert tr.response_status == 200
      assert tr.duration_ms == 15
    end

    test "redacts sensitive headers before persisting", %{api: api, user: user} do
      attrs =
        valid_attrs(api, user)
        |> Map.put(:headers, %{
          "content-type" => "application/json",
          "authorization" => "Bearer secret-token",
          "cookie" => "session=abc123",
          "x-api-key" => "my-secret-key"
        })

      assert {:ok, tr} = Testing.create_test_request(attrs)
      assert tr.headers["authorization"] == "[REDACTED]"
      assert tr.headers["cookie"] == "[REDACTED]"
      assert tr.headers["x-api-key"] == "[REDACTED]"
      assert tr.headers["content-type"] == "application/json"
    end

    test "truncates response_body to 64KB", %{api: api, user: user} do
      large_body = String.duplicate("x", 100_000)
      attrs = Map.put(valid_attrs(api, user), :response_body, large_body)

      assert {:ok, tr} = Testing.create_test_request(attrs)
      assert byte_size(tr.response_body) <= 65_536
    end
  end

  describe "list_test_requests/2" do
    test "returns requests for api ordered by newest first", %{api: api, user: user} do
      {:ok, _r1} = Testing.create_test_request(Map.put(valid_attrs(api, user), :method, "GET"))
      {:ok, _r2} = Testing.create_test_request(Map.put(valid_attrs(api, user), :method, "POST"))

      results = Testing.list_test_requests(api.id)
      assert length(results) == 2
      methods = Enum.map(results, & &1.method)
      assert "GET" in methods
      assert "POST" in methods
    end

    test "respects limit parameter", %{api: api, user: user} do
      for _ <- 1..5 do
        Testing.create_test_request(valid_attrs(api, user))
      end

      results = Testing.list_test_requests(api.id, 3)
      assert length(results) == 3
    end

    test "returns empty list for api with no requests", %{api: _api} do
      assert [] = Testing.list_test_requests(Ecto.UUID.generate())
    end
  end

  describe "get_test_request/1" do
    test "returns a test request by id", %{api: api, user: user} do
      {:ok, created} = Testing.create_test_request(valid_attrs(api, user))
      assert {:ok, found} = Testing.get_test_request(created.id)
      assert found.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Testing.get_test_request(Ecto.UUID.generate())
    end
  end

  describe "clear_history/1" do
    test "deletes all test requests for an api", %{api: api, user: user} do
      for _ <- 1..3 do
        Testing.create_test_request(valid_attrs(api, user))
      end

      assert length(Testing.list_test_requests(api.id)) == 3
      assert {:ok, count} = Testing.clear_history(api.id)
      assert count == 3
      assert Testing.list_test_requests(api.id) == []
    end
  end

  describe "cascade delete" do
    test "deleting API removes its test requests", %{api: api, user: user} do
      {:ok, _tr} = Testing.create_test_request(valid_attrs(api, user))
      assert length(Testing.list_test_requests(api.id)) == 1

      Blackboex.Repo.delete!(api)
      assert Testing.list_test_requests(api.id) == []
    end
  end

  describe "redact_headers/1" do
    test "redacts Authorization header (case-insensitive key)" do
      headers = %{"Authorization" => "Bearer token123"}
      assert Testing.redact_headers(headers)["Authorization"] == "[REDACTED]"
    end

    test "redacts Cookie header" do
      headers = %{"cookie" => "session=abc"}
      assert Testing.redact_headers(headers)["cookie"] == "[REDACTED]"
    end

    test "redacts X-Api-Key header" do
      headers = %{"x-api-key" => "key123"}
      assert Testing.redact_headers(headers)["x-api-key"] == "[REDACTED]"
    end

    test "redacts X-Auth-Token header" do
      headers = %{"X-Auth-Token" => "secret"}
      assert Testing.redact_headers(headers)["X-Auth-Token"] == "[REDACTED]"
    end

    test "redacts X-Access-Token header" do
      headers = %{"X-Access-Token" => "secret"}
      assert Testing.redact_headers(headers)["X-Access-Token"] == "[REDACTED]"
    end

    test "redacts X-Csrf-Token header" do
      headers = %{"x-csrf-token" => "csrfval"}
      assert Testing.redact_headers(headers)["x-csrf-token"] == "[REDACTED]"
    end

    test "redacts Proxy-Authorization header" do
      headers = %{"Proxy-Authorization" => "Basic abc123"}
      assert Testing.redact_headers(headers)["Proxy-Authorization"] == "[REDACTED]"
    end

    test "redacts Set-Cookie header" do
      headers = %{"Set-Cookie" => "session=abc; Path=/"}
      assert Testing.redact_headers(headers)["Set-Cookie"] == "[REDACTED]"
    end

    test "leaves non-sensitive headers unchanged" do
      headers = %{"content-type" => "application/json", "accept" => "text/html"}
      result = Testing.redact_headers(headers)
      assert result["content-type"] == "application/json"
      assert result["accept"] == "text/html"
    end

    test "handles empty map" do
      assert Testing.redact_headers(%{}) == %{}
    end

    test "handles non-map input" do
      assert Testing.redact_headers(nil) == nil
    end
  end

  describe "truncate_body/2" do
    test "returns body unchanged when under limit" do
      body = "short"
      assert Testing.truncate_body(body) == "short"
    end

    test "truncates body to specified max" do
      body = String.duplicate("a", 100)
      result = Testing.truncate_body(body, 50)
      assert byte_size(result) == 50
    end

    test "returns nil for nil body" do
      assert Testing.truncate_body(nil) == nil
    end
  end
end
