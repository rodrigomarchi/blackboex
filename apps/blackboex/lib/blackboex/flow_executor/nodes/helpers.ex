defmodule Blackboex.FlowExecutor.Nodes.Helpers do
  @moduledoc "Shared helpers for flow executor node steps."

  @doc """
  Extracts the current input value and state map from a Reactor step's arguments.

  Handles all argument shapes produced by predecessor node steps:
  - `%{prev_result: %{output: output, state: state}}` — standard node output
  - `%{prev_result: %{value: value, state: state}}` — condition node output
  - `%{prev_result: %{value: value}}` — condition output without state
  - `%{input: input}` — first node after start (state initialises to empty map)
  """
  @spec extract_input_and_state(map()) :: {any(), map()}
  def extract_input_and_state(%{prev_result: %{output: output, state: state}}),
    do: {output, state}

  def extract_input_and_state(%{prev_result: %{value: value, state: state}}),
    do: {value, state}

  def extract_input_and_state(%{prev_result: %{value: value}}),
    do: {value, %{}}

  def extract_input_and_state(%{input: input}),
    do: {input, %{}}

  @doc """
  Executes a zero-arity function in a supervised Task with a timeout.

  The function must return `{:ok, result}` or `{:error, reason}`. If the task
  exceeds `timeout_ms` milliseconds it is killed and an error tuple is returned.
  """
  @spec execute_with_timeout((-> {:ok, any()} | {:error, String.t()}), pos_integer()) ::
          {:ok, any()} | {:error, String.t()}
  def execute_with_timeout(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, "execution timed out after #{timeout_ms}ms"}
    end
  end

  @doc """
  Wraps an output value and state map into the standard node result map.
  """
  @spec wrap_output(any(), map()) :: map()
  def wrap_output(output, state) when is_map(state), do: %{output: output, state: state}
end
