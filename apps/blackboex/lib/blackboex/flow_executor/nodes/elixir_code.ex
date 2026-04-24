defmodule Blackboex.FlowExecutor.Nodes.ElixirCode do
  @moduledoc """
  Reactor step for Elixir Code nodes.
  Evaluates user-provided Elixir code with `input`, `state`, and `env` bindings.

  Code is validated against `Blackboex.CodeGen.ASTValidator` before evaluation:
  dangerous modules (`File`, `System`, `Code`, `Process`, `Application`, etc.),
  Erlang escape hatches (`:os`, `:erlang`, …), `spawn`/`send`/`apply` and
  similar kernel functions, and dynamic module construction are all rejected
  with `{:error, {:security_violation, reasons}}` — no sandbox bypass via
  `:os.cmd`, `:erlang.apply`, `System.get_env`, etc.

  The code can return:
  - A plain value → output is that value, state unchanged
  - A `{output, new_state}` tuple where new_state is a map → output + state updated
  """

  use Reactor.Step

  alias Blackboex.CodeGen.ASTValidator
  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) ::
          {:ok, map()} | {:error, {:security_violation, [String.t()]} | String.t()}
  def run(arguments, context, options) do
    code = Keyword.fetch!(options, :code)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    env = extract_env(context)
    {input, state} = Helpers.extract_input_and_state(arguments)

    case ASTValidator.validate(code) do
      {:ok, _ast} ->
        execute_with_timeout(code, input, state, env, timeout_ms)

      {:error, reasons} ->
        {:error, {:security_violation, reasons}}
    end
  end

  defp execute_with_timeout(code, input, state, env, timeout_ms) do
    Helpers.execute_with_timeout(
      fn ->
        try do
          bindings = [input: input, state: state, env: env]
          {result, _bindings} = Code.eval_string(code, bindings)

          {:ok, output, new_state} = normalize_result(result, state)
          {:ok, %{output: output, state: new_state}}
        rescue
          e -> {:error, sanitize_error_message(Exception.message(e), env)}
        end
      end,
      timeout_ms
    )
  end

  # Minimum byte length for a value to be redacted. Values below this limit
  # (`"1"`, `"true"`, `"GET"`, short booleans / enums) would corrupt
  # unrelated output if we replaced them blindly. Kept in sync with
  # `Blackboex.FlowExecutor.EnvResolver.@redact_min_length` so both layers
  # redact the same set of values. Real secrets are always well above 8 bytes.
  @redact_min_length 8

  # Redact env values from error messages to prevent leaking secrets in
  # stack traces / flow execution outputs.
  @spec sanitize_error_message(String.t(), map()) :: String.t()
  defp sanitize_error_message(message, env) when is_binary(message) and is_map(env) do
    Enum.reduce(env, message, fn {name, value}, acc ->
      if is_binary(value) and byte_size(value) >= @redact_min_length do
        String.replace(acc, value, "{{env.#{name}}}")
      else
        acc
      end
    end)
  end

  defp sanitize_error_message(message, _env), do: to_string(message)

  defp extract_env(context) when is_map(context), do: Map.get(context, :env, %{}) || %{}
  defp extract_env(_context), do: %{}

  @impl true
  @spec undo(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | {:error, any()}
  def undo(value, arguments, context, options) do
    case Keyword.get(options, :undo_code) do
      nil ->
        :ok

      "" ->
        :ok

      undo_code ->
        {input, state} = Helpers.extract_input_and_state(arguments)
        env = extract_env(context)
        timeout_ms = Keyword.get(options, :timeout_ms, 5_000)

        case ASTValidator.validate(undo_code) do
          {:ok, _ast} -> execute_undo(undo_code, input, state, env, value, timeout_ms)
          # undo is best-effort; a violation is silently dropped (same as raises)
          {:error, _reasons} -> :ok
        end
    end
  end

  @impl true
  @spec compensate(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | :retry
  def compensate(reason, _arguments, _context, _options) do
    case reason do
      %ErlangError{original: :timeout} -> :retry
      "execution timed out" <> _ -> :retry
      _ -> :ok
    end
  end

  @impl true
  @spec backoff(any(), Reactor.inputs(), Reactor.context(), keyword()) :: non_neg_integer()
  def backoff(_reason, _arguments, context, _options) do
    retry_count = Map.get(context, :current_try, 0)
    min(round(:math.pow(2, retry_count) * 500), 10_000)
  end

  @spec execute_undo(String.t(), any(), map(), map(), any(), pos_integer()) :: :ok
  defp execute_undo(code, input, state, env, result, timeout_ms) do
    Helpers.execute_with_timeout(
      fn ->
        try do
          bindings = [input: input, state: state, env: env, result: result]
          Code.eval_string(code, bindings)
          {:ok, :ok}
        rescue
          _e -> {:ok, :ok}
        end
      end,
      timeout_ms
    )

    :ok
  end

  defp normalize_result({output, new_state}, _old_state) when is_map(new_state) do
    {:ok, output, new_state}
  end

  defp normalize_result({output, _non_map}, old_state) do
    # Non-map state in tuple: ignore the state update, keep old state
    {:ok, output, old_state}
  end

  defp normalize_result(output, old_state) do
    {:ok, output, old_state}
  end
end
