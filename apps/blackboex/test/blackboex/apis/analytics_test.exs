defmodule Blackboex.Apis.AnalyticsTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit
  @moduletag :capture_log

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.InvocationLog
  alias Blackboex.Repo

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Analytics Org"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Analytics API",
        organization_id: org.id,
        user_id: user.id
      })

    %{api: api}
  end

  defp insert_log(api_id, attrs) do
    %InvocationLog{}
    |> InvocationLog.changeset(
      Map.merge(
        %{api_id: api_id, method: "POST", path: "/", status_code: 200, duration_ms: 100},
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "invocations_count/2" do
    test "counts invocations", %{api: api} do
      insert_log(api.id, %{})
      insert_log(api.id, %{})
      insert_log(api.id, %{})

      assert Analytics.invocations_count(api.id) == 3
    end

    test "returns 0 for no invocations", %{api: api} do
      assert Analytics.invocations_count(api.id) == 0
    end
  end

  describe "success_rate/2" do
    test "calculates success rate", %{api: api} do
      insert_log(api.id, %{status_code: 200})
      insert_log(api.id, %{status_code: 201})
      insert_log(api.id, %{status_code: 500})
      insert_log(api.id, %{status_code: 404})

      assert Analytics.success_rate(api.id) == 50.0
    end

    test "returns 0.0 for no invocations", %{api: api} do
      assert Analytics.success_rate(api.id) == 0.0
    end
  end

  describe "avg_latency/2" do
    test "calculates average latency", %{api: api} do
      insert_log(api.id, %{duration_ms: 100})
      insert_log(api.id, %{duration_ms: 200})
      insert_log(api.id, %{duration_ms: 300})

      assert Analytics.avg_latency(api.id) == 200.0
    end

    test "returns 0.0 for no invocations", %{api: api} do
      assert Analytics.avg_latency(api.id) == 0.0
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
  end
end
