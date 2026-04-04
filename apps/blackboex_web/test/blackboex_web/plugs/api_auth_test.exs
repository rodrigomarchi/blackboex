defmodule BlackboexWeb.Plugs.ApiAuthTest do
  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.Keys
  alias BlackboexWeb.Plugs.ApiAuth

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Auth Test Org"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Auth Test API",
        status: "published",
        source_code: "def handle(params), do: %{ok: true}",
        organization_id: org.id,
        user_id: user.id,
        requires_auth: true
      })

    {:ok, plain_key, _api_key} =
      Keys.create_key(api, %{label: "Test Key", organization_id: org.id})

    metadata = %{
      requires_auth: true,
      visibility: "private",
      api_id: api.id
    }

    %{api: api, org: org, plain_key: plain_key, metadata: metadata}
  end

  describe "authenticate/3" do
    test "authenticates with valid Bearer header", %{api: api, plain_key: key, metadata: meta} do
      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer #{key}")

      assert {:ok, conn} = ApiAuth.authenticate(conn, api, meta)
      assert conn.assigns[:api_key] != nil
    end

    test "returns :missing_key when no key provided", %{api: api, metadata: meta} do
      conn = build_conn(:get, "/api/org/test")
      assert {:error, :missing_key} = ApiAuth.authenticate(conn, api, meta)
    end

    test "returns :invalid for unknown key", %{api: api, metadata: meta} do
      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer bb_live_nonexistent0000000000000000")

      assert {:error, :invalid} = ApiAuth.authenticate(conn, api, meta)
    end

    test "returns :revoked for revoked key", %{
      api: api,
      plain_key: key,
      metadata: meta,
      org: org
    } do
      # Create and revoke a new key
      {:ok, revoked_key_plain, api_key} =
        Keys.create_key(api, %{label: "Revocable", organization_id: org.id})

      {:ok, _} = Keys.revoke_key(api_key)

      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer #{revoked_key_plain}")

      assert {:error, :revoked} = ApiAuth.authenticate(conn, api, meta)
      # Original key should still work
      conn2 =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer #{key}")

      assert {:ok, _} = ApiAuth.authenticate(conn2, api, meta)
    end

    test "returns :expired for expired key", %{api: api, metadata: meta, org: org} do
      {:ok, expired_key, _} =
        Keys.create_key(api, %{
          label: "Expired",
          organization_id: org.id,
          expires_at: DateTime.add(DateTime.utc_now(), -3600)
        })

      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer #{expired_key}")

      assert {:error, :expired} = ApiAuth.authenticate(conn, api, meta)
    end

    test "skips auth when requires_auth is false", %{api: api} do
      meta = %{requires_auth: false, visibility: "public", api_id: api.id}
      conn = build_conn(:get, "/api/org/test")

      assert {:ok, _conn} = ApiAuth.authenticate(conn, api, meta)
    end

    test "skips auth for non-published (compiled) APIs", %{metadata: meta} do
      compiled_api = %{status: "compiled"}
      conn = build_conn(:get, "/api/org/test")

      assert {:ok, _conn} = ApiAuth.authenticate(conn, compiled_api, meta)
    end

    test "returns :invalid when key belongs to different API", %{
      metadata: meta,
      org: org
    } do
      user2 = user_fixture()

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          status: "published",
          organization_id: org.id,
          user_id: user2.id
        })

      {:ok, other_key, _} =
        Keys.create_key(other_api, %{label: "Other", organization_id: org.id})

      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer #{other_key}")

      # meta.api_id is the first API, but the key belongs to other_api
      assert {:error, :invalid} = ApiAuth.authenticate(conn, %{status: "published"}, meta)
    end

    test "skips auth for published API with requires_auth false", %{api: api} do
      meta = %{requires_auth: false, visibility: "public", api_id: api.id}
      published_api = %{api | status: "published"}
      conn = build_conn(:get, "/api/org/test")

      assert {:ok, _conn} = ApiAuth.authenticate(conn, published_api, meta)
    end

    test "handles Bearer without key gracefully", %{api: api, metadata: meta} do
      conn =
        build_conn(:get, "/api/org/test")
        |> put_req_header("authorization", "Bearer ")

      assert {:error, :invalid} = ApiAuth.authenticate(conn, api, meta)
    end
  end
end
