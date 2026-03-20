defmodule BlackboexWeb.PromEx.Plugins.ApiMetricsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias BlackboexWeb.PromEx.Plugins.ApiMetrics

  describe "event_metrics/1" do
    test "returns event metrics struct" do
      result = ApiMetrics.event_metrics(otp_app: :blackboex_web)

      assert %PromEx.MetricTypes.Event{} = result
      assert result.group_name == :blackboex_api_event_metrics
      assert length(result.metrics) == 2
    end
  end
end
