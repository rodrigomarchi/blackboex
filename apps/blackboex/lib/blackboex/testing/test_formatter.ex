defmodule Blackboex.Testing.TestFormatter do
  @moduledoc """
  Custom ExUnit formatter that collects per-test results.
  Used by TestRunner to capture results programmatically.
  """

  use GenServer

  @type test_result :: %{
          name: String.t(),
          status: String.t(),
          duration_ms: non_neg_integer(),
          error: String.t() | nil
        }

  # --- Client API ---

  @spec get_results(pid()) :: [test_result()]
  def get_results(pid) do
    GenServer.call(pid, :get_results)
  end

  # --- GenServer callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{results: []}}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    result = %{
      name: to_string(test.name),
      status: test_status(test.state),
      duration_ms: div(test.time, 1000),
      error: format_error(test.state)
    }

    {:noreply, %{state | results: [result | state.results]}}
  end

  def handle_cast({:suite_finished, _}, state) do
    {:noreply, state}
  end

  def handle_cast({:suite_started, _}, state) do
    {:noreply, state}
  end

  def handle_cast({:module_started, _}, state) do
    {:noreply, state}
  end

  def handle_cast({:module_finished, _}, state) do
    {:noreply, state}
  end

  def handle_cast(_event, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_results, _from, state) do
    {:reply, Enum.reverse(state.results), state}
  end

  # --- Private ---

  # OTP 26+ requires format_status to be public (GenServer callback)
  @impl true
  def format_status(status), do: status

  defp test_status(nil), do: "passed"
  defp test_status({:excluded, _}), do: "excluded"
  defp test_status({:skipped, _}), do: "skipped"
  defp test_status({:failed, _}), do: "failed"
  defp test_status({:invalid, _}), do: "error"

  defp format_error(nil), do: nil

  defp format_error({:failed, failures}) do
    failures
    |> Enum.map(fn
      {_, %ExUnit.AssertionError{} = err} ->
        "Expected: #{inspect(err.left)}\nGot: #{inspect(err.right)}\n#{err.message}"

      {_, %{message: msg}} ->
        msg

      {_, error} ->
        inspect(error)
    end)
    |> Enum.join("\n\n")
  end

  defp format_error(_), do: nil
end
