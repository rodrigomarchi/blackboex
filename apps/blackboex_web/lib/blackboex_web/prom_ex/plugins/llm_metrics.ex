defmodule BlackboexWeb.PromEx.Plugins.LlmMetrics do
  @moduledoc """
  PromEx plugin for LLM call metrics.

  Listens to `[:blackboex, :llm, :call]` telemetry events emitted
  by `Blackboex.Telemetry.Events`.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :llm))

    Event.build(
      :blackboex_llm_event_metrics,
      [
        distribution(
          metric_prefix ++ [:request, :duration, :milliseconds],
          event_name: [:blackboex, :llm, :call],
          measurement: :duration,
          description: "Duration of LLM requests in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1_000, 2_500, 5_000, 10_000, 30_000]
          ],
          tags: [:provider, :model],
          unit: :millisecond
        ),
        sum(
          metric_prefix ++ [:tokens, :total],
          event_name: [:blackboex, :llm, :call],
          measurement: fn measurements ->
            Map.get(measurements, :input_tokens, 0) + Map.get(measurements, :output_tokens, 0)
          end,
          description: "Total tokens consumed by LLM calls.",
          tags: [:provider, :model]
        ),
        counter(
          metric_prefix ++ [:requests, :total],
          event_name: [:blackboex, :llm, :call],
          description: "Total number of LLM requests.",
          measurement: fn _measurements -> 1 end,
          tags: [:provider, :model]
        )
      ]
    )
  end
end
