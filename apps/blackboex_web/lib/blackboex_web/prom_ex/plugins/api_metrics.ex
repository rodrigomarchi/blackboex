defmodule BlackboexWeb.PromEx.Plugins.ApiMetrics do
  @moduledoc """
  PromEx plugin for API invocation metrics.

  Listens to `[:blackboex, :api, :request]` telemetry events emitted
  by `Blackboex.Telemetry.Events`.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :api))

    Event.build(
      :blackboex_api_event_metrics,
      [
        counter(
          metric_prefix ++ [:invocations, :total],
          event_name: [:blackboex, :api, :request],
          description: "Total number of API invocations.",
          measurement: fn _measurements -> 1 end,
          tags: [:api_id, :method, :status]
        ),
        distribution(
          metric_prefix ++ [:invocation, :duration, :milliseconds],
          event_name: [:blackboex, :api, :request],
          measurement: :duration,
          description: "Duration of API invocations in milliseconds.",
          reporter_options: [
            buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000]
          ],
          tags: [:api_id, :method, :status],
          unit: :millisecond
        )
      ]
    )
  end
end
