defmodule Blackboex.Agent.Guardrails do
  @moduledoc """
  Safety guardrails for the code generation agent.

  Controls the `should_continue?` callback for LangChain's step mode,
  enforcing limits on iterations, cost, time, and detecting stuck loops.
  """

  alias Blackboex.Conversations
  alias Blackboex.Conversations.Run

  @type config :: %{
          max_iterations: pos_integer(),
          max_time_ms: pos_integer(),
          max_cost_cents: pos_integer(),
          max_consecutive_same_tool: pos_integer(),
          max_compile_attempts: pos_integer(),
          max_test_attempts: pos_integer()
        }

  @type check_result :: :continue | {:stop, reason :: atom()}

  @default_config %{
    max_iterations: 15,
    max_time_ms: 300_000,
    max_cost_cents: 50,
    max_consecutive_same_tool: 3,
    max_compile_attempts: 5,
    max_test_attempts: 3
  }

  @doc "Returns the default guardrail configuration."
  @spec default_config() :: config()
  def default_config, do: @default_config

  @doc """
  Checks all guardrails for a run. Returns `:continue` if safe to proceed,
  or `{:stop, reason}` if a limit has been reached.
  """
  @spec check(Run.t(), config()) :: check_result()
  def check(%Run{} = run, config \\ @default_config) do
    checks = [
      &check_iterations(&1, config),
      &check_time(&1, config),
      &check_cost(&1, config),
      &check_tool_limits(&1, config),
      &check_stuck_loop/1
    ]

    Enum.find_value(checks, :continue, fn check_fn ->
      case check_fn.(run) do
        :continue -> nil
        {:stop, _reason} = stop -> stop
      end
    end)
  end

  @spec check_iterations(Run.t(), config()) :: check_result()
  defp check_iterations(%Run{iteration_count: count}, config) do
    if count >= config.max_iterations do
      {:stop, :max_iterations}
    else
      :continue
    end
  end

  @spec check_time(Run.t(), config()) :: check_result()
  defp check_time(%Run{started_at: nil}, _config), do: :continue

  defp check_time(%Run{started_at: started_at}, config) do
    elapsed = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

    if elapsed >= config.max_time_ms do
      {:stop, :max_time}
    else
      :continue
    end
  end

  @spec check_cost(Run.t(), config()) :: check_result()
  defp check_cost(%Run{cost_cents: cost}, config) do
    if cost >= config.max_cost_cents do
      {:stop, :max_cost}
    else
      :continue
    end
  end

  @spec check_tool_limits(Run.t(), config()) :: check_result()
  defp check_tool_limits(%Run{id: run_id}, config) do
    compile_count = Conversations.count_tool_calls(run_id, "compile_code")
    test_count = Conversations.count_tool_calls(run_id, "run_tests")

    cond do
      compile_count >= config.max_compile_attempts -> {:stop, :max_compile_attempts}
      test_count >= config.max_test_attempts -> {:stop, :max_test_attempts}
      true -> :continue
    end
  end

  @spec check_stuck_loop(Run.t()) :: check_result()
  defp check_stuck_loop(%Run{id: run_id}) do
    recent = Conversations.recent_tool_calls(run_id, 3)
    tool_names = Enum.map(recent, & &1.tool_name)

    if length(tool_names) == 3 and length(Enum.uniq(tool_names)) == 1 do
      {:stop, :stuck_loop}
    else
      :continue
    end
  end

  @spec reason_message(atom()) :: String.t()
  def reason_message(:max_iterations),
    do: "Maximum iterations reached. Submit your best version now using submit_code."

  def reason_message(:max_time),
    do: "Time limit reached. Submit your best version now using submit_code."

  def reason_message(:max_cost),
    do: "Cost limit reached. Submit your best version now using submit_code."

  def reason_message(:max_compile_attempts),
    do:
      "Maximum compilation attempts reached. Submit your current best version using submit_code."

  def reason_message(:max_test_attempts),
    do: "Maximum test attempts reached. Submit your current code and tests using submit_code."

  def reason_message(:stuck_loop),
    do:
      "You appear stuck in a loop calling the same tool repeatedly. " <>
        "Try a different approach or submit your best version using submit_code."

  def reason_message(reason),
    do: "Guardrail triggered: #{reason}. Submit your best version now using submit_code."
end
