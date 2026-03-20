defmodule Blackboex.Apis.MetricRollupTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.MetricRollup

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{
        api_id: Ecto.UUID.generate(),
        date: ~D[2026-03-20],
        hour: 14
      }

      changeset = MetricRollup.changeset(%MetricRollup{}, attrs)
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        api_id: Ecto.UUID.generate(),
        date: ~D[2026-03-20],
        hour: 14,
        invocations: 100,
        errors: 5,
        avg_duration_ms: 42.5,
        p95_duration_ms: 150.0,
        unique_consumers: 20
      }

      changeset = MetricRollup.changeset(%MetricRollup{}, attrs)
      assert changeset.valid?
    end

    test "invalid without api_id" do
      attrs = %{date: ~D[2026-03-20], hour: 14}
      changeset = MetricRollup.changeset(%MetricRollup{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:api_id]
    end

    test "invalid with hour out of range" do
      attrs = %{api_id: Ecto.UUID.generate(), date: ~D[2026-03-20], hour: 25}
      changeset = MetricRollup.changeset(%MetricRollup{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:hour]
    end

    test "invalid with negative invocations" do
      attrs = %{api_id: Ecto.UUID.generate(), date: ~D[2026-03-20], hour: 0, invocations: -1}
      changeset = MetricRollup.changeset(%MetricRollup{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:invocations]
    end
  end
end
