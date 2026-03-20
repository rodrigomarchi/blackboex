defmodule BlackboexWeb.PromEx.Plugins.LlmMetricsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias BlackboexWeb.PromEx.Plugins.LlmMetrics

  describe "event_metrics/1" do
    test "returns event metrics struct" do
      result = LlmMetrics.event_metrics(otp_app: :blackboex_web)

      assert %PromEx.MetricTypes.Event{} = result
      assert result.group_name == :blackboex_llm_event_metrics
      assert length(result.metrics) == 3
    end
  end
end
