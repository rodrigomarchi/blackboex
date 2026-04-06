defmodule Blackboex.Apis.MetricRollupWorkerTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.InvocationLog
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Apis.MetricRollupWorker

  defp setup_test_api(_context) do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      %Api{}
      |> Api.changeset(%{
        name: "Test API",
        slug: "test-api",
        description: "A test API",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })
      |> Repo.insert()

    %{api: api, org: org, user: user}
  end

  describe "perform/1" do
    setup [:setup_test_api]

    test "aggregates invocation_logs into metric_rollup", %{api: api} do
      now = NaiveDateTime.utc_now()
      date = NaiveDateTime.to_date(now)
      hour = now.hour

      # Insert logs in the current hour
      for i <- 1..5 do
        invocation_log_fixture(%{
          api_id: api.id,
          duration_ms: i * 10,
          status_code: if(i == 5, do: 500, else: 200),
          ip_address: "10.0.0.#{i}"
        })
      end

      job = %Oban.Job{args: %{"date" => Date.to_iso8601(date), "hour" => hour}}
      assert :ok = MetricRollupWorker.perform(job)

      rollup = Repo.get_by!(MetricRollup, api_id: api.id, date: date, hour: hour)
      assert rollup.invocations == 5
      assert rollup.errors == 1
      assert rollup.unique_consumers == 5
      assert rollup.avg_duration_ms > 0
      assert rollup.p95_duration_ms > 0
    end

    test "is idempotent — re-running does not duplicate", %{api: api} do
      now = NaiveDateTime.utc_now()
      date = NaiveDateTime.to_date(now)
      hour = now.hour

      invocation_log_fixture(%{api_id: api.id, duration_ms: 100, ip_address: "10.0.0.1"})

      job = %Oban.Job{args: %{"date" => Date.to_iso8601(date), "hour" => hour}}
      assert :ok = MetricRollupWorker.perform(job)
      assert :ok = MetricRollupWorker.perform(job)

      count =
        MetricRollup
        |> Ecto.Query.where(api_id: ^api.id, date: ^date, hour: ^hour)
        |> Repo.aggregate(:count)

      assert count == 1
    end

    test "no logs produces no rollup", %{api: _api} do
      job = %Oban.Job{args: %{"date" => "2020-01-01", "hour" => 0}}
      assert :ok = MetricRollupWorker.perform(job)

      assert Repo.aggregate(MetricRollup, :count) == 0
    end

    test "aggregates multiple APIs independently", %{api: api, org: org, user: user} do
      {:ok, api2} =
        %Api{}
        |> Api.changeset(%{
          name: "Second API",
          slug: "second-api",
          description: "Another API",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id
        })
        |> Repo.insert()

      now = NaiveDateTime.utc_now()
      date = NaiveDateTime.to_date(now)
      hour = now.hour

      invocation_log_fixture(%{api_id: api.id, duration_ms: 100, ip_address: "10.0.0.1"})
      invocation_log_fixture(%{api_id: api.id, duration_ms: 200, ip_address: "10.0.0.2"})

      invocation_log_fixture(%{
        api_id: api2.id,
        duration_ms: 50,
        ip_address: "10.0.0.3",
        status_code: 500
      })

      job = %Oban.Job{args: %{"date" => Date.to_iso8601(date), "hour" => hour}}
      assert :ok = MetricRollupWorker.perform(job)

      rollup1 = Repo.get_by!(MetricRollup, api_id: api.id, date: date, hour: hour)
      assert rollup1.invocations == 2
      assert rollup1.errors == 0
      assert rollup1.unique_consumers == 2

      rollup2 = Repo.get_by!(MetricRollup, api_id: api2.id, date: date, hour: hour)
      assert rollup2.invocations == 1
      assert rollup2.errors == 1
      assert rollup2.unique_consumers == 1
    end

    test "handles specific date and hour boundaries", %{api: api} do
      # Insert log at exactly midnight boundary
      job = %Oban.Job{args: %{"date" => "2026-03-19", "hour" => 23}}

      # Insert log at 23:30 on 2026-03-19
      log_time = ~N[2026-03-19 23:30:00]

      %InvocationLog{}
      |> InvocationLog.changeset(%{
        api_id: api.id,
        method: "POST",
        path: "/api/test",
        status_code: 200,
        duration_ms: 75,
        request_body_size: 0,
        response_body_size: 100,
        ip_address: "10.0.0.1"
      })
      |> Repo.insert!()
      |> Ecto.Changeset.change(inserted_at: log_time)
      |> Repo.update!()

      assert :ok = MetricRollupWorker.perform(job)

      rollup = Repo.get_by!(MetricRollup, api_id: api.id, date: ~D[2026-03-19], hour: 23)
      assert rollup.invocations == 1
      assert rollup.p95_duration_ms == 75.0
    end

    test "default args uses previous hour" do
      job = %Oban.Job{args: %{}}
      # Should not crash even with no data
      assert :ok = MetricRollupWorker.perform(job)
    end

    test "partial failure returns error with count of failed APIs", %{api: api} do
      now = NaiveDateTime.utc_now()
      date = NaiveDateTime.to_date(now)
      hour = now.hour

      # Insert valid log for the real API
      invocation_log_fixture(%{api_id: api.id, duration_ms: 100, ip_address: "10.0.0.1"})

      # Insert a log with a nonexistent api_id by temporarily disabling FK checks.
      # The aggregation will find it, but the rollup upsert will fail on FK.
      fake_api_id = Ecto.UUID.generate()

      Repo.query!("SET session_replication_role = 'replica'")

      Repo.query!(
        """
        INSERT INTO invocation_logs
          (id, api_id, method, path, status_code, duration_ms,
           request_body_size, response_body_size, ip_address, inserted_at)
        VALUES (gen_random_uuid(), $1, 'GET', '/test', 200, 50, 0, 100, '10.0.0.99', $2)
        """,
        [Ecto.UUID.dump!(fake_api_id), NaiveDateTime.utc_now()]
      )

      Repo.query!("SET session_replication_role = 'origin'")

      job = %Oban.Job{args: %{"date" => Date.to_iso8601(date), "hour" => hour}}
      result = MetricRollupWorker.perform(job)

      assert {:error, msg} = result
      assert msg =~ "1 API metric rollups failed"

      # The valid API's rollup was still created
      rollup = Repo.get_by(MetricRollup, api_id: api.id, date: date, hour: hour)
      assert rollup != nil
      assert rollup.invocations == 1
    end
  end
end
