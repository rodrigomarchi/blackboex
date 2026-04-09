defmodule Blackboex.FlowExecutor.Nodes.ForEach do
  @moduledoc "For-each node — iterates over a collection, processing each item with code."
  use Reactor.Step
  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    source_expression = Keyword.fetch!(options, :source_expression)
    body_code = Keyword.fetch!(options, :body_code)
    item_variable = Keyword.get(options, :item_variable, "item")
    accumulator = Keyword.get(options, :accumulator, "results")
    batch_size = Keyword.get(options, :batch_size, 10)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)

    with {:ok, items} <- eval_source(source_expression, input, state),
         :ok <- validate_list(items),
         {:ok, results} <-
           process_items(items, body_code, item_variable, state, batch_size, timeout_ms) do
      new_state = Map.put(state, accumulator, results)
      {:ok, Helpers.wrap_output(results, new_state)}
    end
  end

  @spec eval_source(String.t(), any(), map()) :: {:ok, any()} | {:error, String.t()}
  defp eval_source(expression, input, state) do
    {result, _bindings} = Code.eval_string(expression, input: input, state: state)
    {:ok, result}
  rescue
    e -> {:error, "source_expression evaluation failed: #{Exception.message(e)}"}
  end

  @spec validate_list(any()) :: :ok | {:error, String.t()}
  defp validate_list(items) when is_list(items), do: :ok

  defp validate_list(other),
    do: {:error, "source_expression must return a list, got: #{inspect(other)}"}

  # item_variable is validated by BlackboexFlow (validate_optional_identifier: /^\w+$/)
  # and flows are capped at @max_nodes=100, so atom table growth is bounded.
  @max_var_length 32

  @spec process_items(list(), String.t(), String.t(), map(), pos_integer(), pos_integer()) ::
          {:ok, list()} | {:error, String.t()}
  defp process_items(items, body_code, item_variable, state, batch_size, timeout_ms) do
    item_var_atom = safe_to_atom(item_variable)

    items
    |> Enum.with_index()
    |> Task.async_stream(
      fn {item, index} ->
        bindings = [{item_var_atom, item}, {:state, state}, {:index, index}]
        eval_body(body_code, bindings)
      end,
      max_concurrency: batch_size,
      timeout: timeout_ms,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, &collect_result(&1, &2, timeout_ms))
  end

  @spec eval_body(String.t(), keyword()) :: {:ok, any()} | {:error, String.t()}
  defp eval_body(body_code, bindings) do
    {result, _} = Code.eval_string(body_code, bindings)
    {:ok, result}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @spec collect_result(
          {:ok, {:ok, any()} | {:error, String.t()}} | {:exit, any()},
          {:ok, list()},
          pos_integer()
        ) :: {:cont, {:ok, list()}} | {:halt, {:error, String.t()}}
  defp collect_result({:ok, {:ok, result}}, {:ok, acc}, _timeout_ms) do
    {:cont, {:ok, acc ++ [result]}}
  end

  defp collect_result({:ok, {:error, reason}}, _acc, _timeout_ms) do
    {:halt, {:error, "item processing failed: #{reason}"}}
  end

  defp collect_result({:exit, :timeout}, _acc, timeout_ms) do
    {:halt, {:error, "item processing timed out after #{timeout_ms}ms"}}
  end

  defp collect_result({:exit, reason}, _acc, _timeout_ms) do
    {:halt, {:error, "item processing failed: #{inspect(reason)}"}}
  end

  @spec safe_to_atom(String.t()) :: atom()
  defp safe_to_atom(name) when is_binary(name) and byte_size(name) <= @max_var_length do
    if Regex.match?(~r/^\w+$/, name) do
      String.to_atom(name)
    else
      :item
    end
  end

  defp safe_to_atom(_), do: :item
end
