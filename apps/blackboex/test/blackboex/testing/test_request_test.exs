defmodule Blackboex.Testing.TestRequestTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Testing.TestRequest

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        api_id: Ecto.UUID.generate(),
        user_id: 1,
        method: "GET",
        path: "/api/user/slug",
        headers: %{"content-type" => "application/json"},
        response_status: 200,
        response_headers: %{"content-type" => "application/json"},
        response_body: ~s({"ok": true}),
        duration_ms: 42
      }

      changeset = TestRequest.changeset(%TestRequest{}, attrs)
      assert changeset.valid?
    end

    test "requires method" do
      changeset = TestRequest.changeset(%TestRequest{}, %{path: "/api/u/s"})
      assert %{method: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires path" do
      changeset = TestRequest.changeset(%TestRequest{}, %{method: "GET"})
      assert %{path: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires api_id" do
      changeset =
        TestRequest.changeset(%TestRequest{}, %{method: "GET", path: "/api/u/s"})

      assert %{api_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates method is a valid HTTP method" do
      changeset =
        TestRequest.changeset(%TestRequest{}, %{
          method: "INVALID",
          path: "/api/u/s",
          api_id: Ecto.UUID.generate()
        })

      assert %{method: ["is invalid"]} = errors_on(changeset)
    end

    test "allows body to be nil" do
      attrs = %{
        api_id: Ecto.UUID.generate(),
        method: "GET",
        path: "/api/u/s",
        response_status: 200,
        duration_ms: 10
      }

      changeset = TestRequest.changeset(%TestRequest{}, attrs)
      assert changeset.valid?
    end
  end
end
