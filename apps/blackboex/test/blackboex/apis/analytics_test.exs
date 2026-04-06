defmodule Blackboex.Apis.AnalyticsTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit
  @moduletag :capture_log

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.InvocationLog
  alias Blackboex.Repo

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Apis.create_api(%{
        name: "Analytics API",
        organization_id: org.id,
        user_id: user.id
      })

    %{api: api}
  end

  defp insert_log_at(api_id, attrs, seconds_ago) do
    inserted_at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-seconds_ago, :second)
      |> NaiveDateTime.truncate(:second)

    invocation_log_fixture(Map.put(attrs, :api_id, api_id))
    |> Ecto.Changeset.change(%{inserted_at: inserted_at})
    |> Repo.update!()
  end

  describe "invocations_count/2" do
    test "counts invocations", %{api: api} do
      invocation_log_fixture(%{api_id: api.id})
      invocation_log_fixture(%{api_id: api.id})
      invocation_log_fixture(%{api_id: api.id})

      assert Analytics.invocations_count(api.id) == 3
    end

    test "returns 0 for no invocations", %{api: api} do
      assert Analytics.invocations_count(api.id) == 0
    end

    test "counts only invocations for the given api_id", %{api: api} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org"})

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          organization_id: other_org.id,
          user_id: other_user.id
        })

      invocation_log_fixture(%{api_id: api.id})
      invocation_log_fixture(%{api_id: api.id})
      invocation_log_fixture(%{api_id: other_api.id})

      assert Analytics.invocations_count(api.id) == 2
      assert Analytics.invocations_count(other_api.id) == 1
    end

    test "filters by :day period", %{api: api} do
      insert_log_at(api.id, %{}, 3_600)
      insert_log_at(api.id, %{}, 172_800)

      assert Analytics.invocations_count(api.id, period: :day) == 1
    end

    test "filters by :week period", %{api: api} do
      insert_log_at(api.id, %{}, 86_400)
      insert_log_at(api.id, %{}, 691_200)

      assert Analytics.invocations_count(api.id, period: :week) == 1
    end

    test "filters by :month period", %{api: api} do
      insert_log_at(api.id, %{}, 86_400)
      insert_log_at(api.id, %{}, 2_678_400)

      assert Analytics.invocations_count(api.id, period: :month) == 1
    end

    test ":all period returns everything", %{api: api} do
      insert_log_at(api.id, %{}, 10_000_000)
      invocation_log_fixture(%{api_id: api.id})

      assert Analytics.invocations_count(api.id, period: :all) == 2
    end
  end

  describe "success_rate/2" do
    test "calculates success rate", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})
      invocation_log_fixture(%{api_id: api.id, status_code: 201})
      invocation_log_fixture(%{api_id: api.id, status_code: 500})
      invocation_log_fixture(%{api_id: api.id, status_code: 404})

      assert Analytics.success_rate(api.id) == 50.0
    end

    test "returns 0.0 for no invocations", %{api: api} do
      assert Analytics.success_rate(api.id) == 0.0
    end

    test "returns 100.0 when all requests succeed", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})
      invocation_log_fixture(%{api_id: api.id, status_code: 201})
      invocation_log_fixture(%{api_id: api.id, status_code: 299})

      assert Analytics.success_rate(api.id) == 100.0
    end

    test "returns 0.0 when all requests fail", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 400})
      invocation_log_fixture(%{api_id: api.id, status_code: 500})

      assert Analytics.success_rate(api.id) == 0.0
    end

    test "filters by :day period", %{api: api} do
      insert_log_at(api.id, %{status_code: 200}, 3_600)
      insert_log_at(api.id, %{status_code: 500}, 172_800)

      assert Analytics.success_rate(api.id, period: :day) == 100.0
    end
  end

  describe "avg_latency/2" do
    test "calculates average latency", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, duration_ms: 100})
      invocation_log_fixture(%{api_id: api.id, duration_ms: 200})
      invocation_log_fixture(%{api_id: api.id, duration_ms: 300})

      assert Analytics.avg_latency(api.id) == 200.0
    end

    test "returns 0.0 for no invocations", %{api: api} do
      assert Analytics.avg_latency(api.id) == 0.0
    end

    test "returns single value when one log exists", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, duration_ms: 150})

      assert Analytics.avg_latency(api.id) == 150.0
    end

    test "filters by :week period", %{api: api} do
      insert_log_at(api.id, %{duration_ms: 50}, 86_400)
      insert_log_at(api.id, %{duration_ms: 900}, 691_200)

      assert Analytics.avg_latency(api.id, period: :week) == 50.0
    end
  end

  describe "error_count/2" do
    test "counts error responses (4xx and 5xx)", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})
      invocation_log_fixture(%{api_id: api.id, status_code: 404})
      invocation_log_fixture(%{api_id: api.id, status_code: 500})
      invocation_log_fixture(%{api_id: api.id, status_code: 422})

      assert Analytics.error_count(api.id) == 3
    end

    test "returns 0 when no errors", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})
      invocation_log_fixture(%{api_id: api.id, status_code: 201})

      assert Analytics.error_count(api.id) == 0
    end

    test "returns 0 for no invocations", %{api: api} do
      assert Analytics.error_count(api.id) == 0
    end

    test "counts exactly at 400 boundary", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 399})
      invocation_log_fixture(%{api_id: api.id, status_code: 400})

      assert Analytics.error_count(api.id) == 1
    end

    test "filters by :day period", %{api: api} do
      insert_log_at(api.id, %{status_code: 500}, 3_600)
      insert_log_at(api.id, %{status_code: 500}, 172_800)

      assert Analytics.error_count(api.id, period: :day) == 1
    end

    test "filters by :month period", %{api: api} do
      insert_log_at(api.id, %{status_code: 404}, 86_400)
      insert_log_at(api.id, %{status_code: 404}, 2_678_400)

      assert Analytics.error_count(api.id, period: :month) == 1
    end
  end

  describe "recent_errors/2" do
    test "returns recent error logs ordered by descending insertion time", %{api: api} do
      insert_log_at(api.id, %{status_code: 500}, 300)
      insert_log_at(api.id, %{status_code: 404}, 200)
      insert_log_at(api.id, %{status_code: 422}, 100)

      errors = Analytics.recent_errors(api.id)

      assert length(errors) == 3
      [first | _] = errors
      assert first.status_code == 422
    end

    test "excludes successful responses", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})
      invocation_log_fixture(%{api_id: api.id, status_code: 201})
      invocation_log_fixture(%{api_id: api.id, status_code: 500})

      errors = Analytics.recent_errors(api.id)

      assert length(errors) == 1
      assert hd(errors).status_code == 500
    end

    test "returns empty list when no errors", %{api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200})

      assert Analytics.recent_errors(api.id) == []
    end

    test "respects limit parameter", %{api: api} do
      for _ <- 1..5 do
        invocation_log_fixture(%{api_id: api.id, status_code: 500})
      end

      errors = Analytics.recent_errors(api.id, 3)

      assert length(errors) == 3
    end

    test "defaults to limit 10", %{api: api} do
      for _ <- 1..15 do
        invocation_log_fixture(%{api_id: api.id, status_code: 500})
      end

      errors = Analytics.recent_errors(api.id)

      assert length(errors) == 10
    end

    test "returns only errors for given api_id", %{api: api} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org 2"})

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API 2",
          organization_id: other_org.id,
          user_id: other_user.id
        })

      invocation_log_fixture(%{api_id: api.id, status_code: 500})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 500})

      errors = Analytics.recent_errors(api.id)

      assert length(errors) == 1
      assert hd(errors).api_id == api.id
    end
  end

  describe "log_invocation/1" do
    test "persists invocation log asynchronously", %{api: api} do
      :ok =
        Analytics.log_invocation(%{
          api_id: api.id,
          method: "GET",
          path: "/test",
          status_code: 200,
          duration_ms: 42,
          request_body_size: 0,
          response_body_size: 128,
          ip_address: "127.0.0.1"
        })

      # Give async task time to complete
      Process.sleep(100)

      assert Analytics.invocations_count(api.id) == 1
    end

    test "returns :ok even with invalid attrs", %{api: api} do
      # Invalid: missing required method field
      result = Analytics.log_invocation(%{api_id: api.id})

      assert result == :ok
    end

    test "returns :ok for completely empty attrs" do
      result = Analytics.log_invocation(%{})

      assert result == :ok
    end
  end

  describe "invocation_log changeset" do
    test "validates required fields" do
      changeset = InvocationLog.changeset(%InvocationLog{}, %{})
      assert errors_on(changeset).api_id
      assert errors_on(changeset).method
    end

    test "validates path max length" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          path: String.duplicate("a", 2049)
        })

      assert errors_on(changeset).path
    end

    test "validates method max length" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: String.duplicate("X", 11)
        })

      assert errors_on(changeset).method
    end

    test "validates status_code range" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          status_code: 99
        })

      assert errors_on(changeset).status_code

      changeset2 =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          status_code: 600
        })

      assert errors_on(changeset2).status_code
    end

    test "validates duration_ms is non-negative" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          duration_ms: -1
        })

      assert errors_on(changeset).duration_ms
    end

    test "validates ip_address max length" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          ip_address: String.duplicate("1", 46)
        })

      assert errors_on(changeset).ip_address
    end

    test "accepts valid attrs" do
      changeset =
        InvocationLog.changeset(%InvocationLog{}, %{
          api_id: Ecto.UUID.generate(),
          method: "GET",
          path: "/test",
          status_code: 200,
          duration_ms: 100,
          ip_address: "127.0.0.1"
        })

      assert changeset.valid?
    end
  end
end
