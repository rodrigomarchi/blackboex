defmodule Blackboex.FlowExecutor.Nodes.HttpRequest do
  @moduledoc """
  Reactor step for HTTP Request nodes.

  Calls an external HTTP endpoint with optional interpolation of `{{state.key}}`
  and `{{input.key}}` placeholders in the URL, headers, and body template.

  Supports bearer, basic, and API-key authentication. Retries automatically on
  timeouts and 5xx responses via `compensate/4` and `backoff/4`.
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(arguments, _context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    method =
      options
      |> Keyword.fetch!(:method)
      |> String.downcase()
      |> String.to_existing_atom()

    url = options |> Keyword.fetch!(:url) |> interpolate(input, state)

    headers =
      options
      |> Keyword.get(:headers, %{})
      |> interpolate_map(input, state)

    body_template = Keyword.get(options, :body_template, "")
    timeout_ms = Keyword.get(options, :timeout_ms, 10_000)
    expected_status = Keyword.get(options, :expected_status, [200, 201])
    auth_type = Keyword.get(options, :auth_type, "none")
    auth_config = Keyword.get(options, :auth_config, %{})

    headers = apply_auth(headers, auth_type, auth_config)
    body = if body_template != "", do: interpolate(body_template, input, state), else: nil

    req_opts =
      [
        method: method,
        url: url,
        headers: Map.to_list(headers),
        receive_timeout: timeout_ms
      ]
      |> maybe_put_body(body)
      |> maybe_put_plug(options)

    start_time = System.monotonic_time(:millisecond)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        duration = System.monotonic_time(:millisecond) - start_time

        result = %{
          status: status,
          headers: Map.new(resp_headers),
          body: resp_body,
          duration_ms: duration
        }

        if status in expected_status do
          new_state = Map.put(state, "http_response", result)
          {:ok, Helpers.wrap_output(result, new_state)}
        else
          {:error, "HTTP #{status}: unexpected status (expected #{inspect(expected_status)})"}
        end

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "HTTP request timed out after #{timeout_ms}ms"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  @spec compensate(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | :retry
  def compensate(reason, _arguments, _context, _options) do
    case reason do
      "HTTP request timed out" <> _ -> :retry
      "HTTP 5" <> _ -> :retry
      _ -> :ok
    end
  end

  @impl true
  @spec backoff(any(), Reactor.inputs(), Reactor.context(), keyword()) :: non_neg_integer()
  def backoff(_reason, _arguments, context, _options) do
    retry_count = Map.get(context, :current_try, 0)
    base = min(round(:math.pow(2, retry_count) * 500), 15_000)
    base + :rand.uniform(500)
  end

  # ---------------------------------------------------------------------------
  # Private — interpolation
  # ---------------------------------------------------------------------------

  @spec interpolate(String.t(), any(), map()) :: String.t()
  defp interpolate(template, input, state) when is_binary(template) do
    Regex.replace(~r/\{\{(\w+)\.(\w+)\}\}/, template, fn _, scope, key ->
      resolve_placeholder(scope, key, input, state)
    end)
  end

  @spec interpolate_map(map(), any(), map()) :: map()
  defp interpolate_map(headers, input, state) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {k, interpolate(v, input, state)} end)
  end

  @spec resolve_placeholder(String.t(), String.t(), any(), map()) :: String.t()
  defp resolve_placeholder("state", key, _input, state) when is_map(state) do
    state |> Map.get(key, "") |> to_string()
  end

  defp resolve_placeholder("input", key, input, _state) when is_map(input) do
    input |> Map.get(key, "") |> to_string()
  end

  defp resolve_placeholder(_scope, _key, _input, _state), do: ""

  # ---------------------------------------------------------------------------
  # Private — auth
  # ---------------------------------------------------------------------------

  @spec apply_auth(map(), String.t(), map()) :: map()
  defp apply_auth(headers, "bearer", %{"token" => token}) do
    Map.put(headers, "authorization", "Bearer #{token}")
  end

  defp apply_auth(headers, "basic", %{"username" => user, "password" => pass}) do
    encoded = Base.encode64("#{user}:#{pass}")
    Map.put(headers, "authorization", "Basic #{encoded}")
  end

  defp apply_auth(headers, "api_key", %{"key_name" => name, "key_value" => value}) do
    Map.put(headers, name, value)
  end

  defp apply_auth(headers, _auth_type, _auth_config), do: headers

  # ---------------------------------------------------------------------------
  # Private — request building helpers
  # ---------------------------------------------------------------------------

  @spec maybe_put_body(keyword(), String.t() | nil) :: keyword()
  defp maybe_put_body(opts, nil), do: opts
  defp maybe_put_body(opts, body), do: Keyword.put(opts, :body, body)

  @spec maybe_put_plug(keyword(), keyword()) :: keyword()
  defp maybe_put_plug(opts, options) do
    opts
    |> maybe_merge_key(options, :plug)
    |> maybe_merge_key(options, :retry)
  end

  @spec maybe_merge_key(keyword(), keyword(), atom()) :: keyword()
  defp maybe_merge_key(opts, options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> Keyword.put(opts, key, value)
      :error -> opts
    end
  end
end
