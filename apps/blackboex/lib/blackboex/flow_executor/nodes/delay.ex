defmodule Blackboex.FlowExecutor.Nodes.Delay do
  @moduledoc "Delay node — pauses execution for a configured duration."
  use Reactor.Step
  alias Blackboex.FlowExecutor.Nodes.Helpers

  @max_allowed_duration_ms 300_000

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()}
  def run(arguments, _context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    duration_ms = Keyword.fetch!(options, :duration_ms)
    max_duration_ms = Keyword.get(options, :max_duration_ms, 60_000)
    absolute_max_ms = Keyword.get(options, :absolute_max_ms, @max_allowed_duration_ms)

    actual_duration =
      duration_ms
      |> min(max_duration_ms)
      |> min(absolute_max_ms)
      |> max(0)

    Process.sleep(actual_duration)

    new_state = Map.put(state, "delayed_ms", actual_duration)
    {:ok, Helpers.wrap_output(input, new_state)}
  end
end
