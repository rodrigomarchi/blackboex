defmodule Blackboex.Playgrounds.Http do
  @moduledoc """
  Safe HTTP client for playground sandbox execution.

  Provides a controlled surface for making HTTP requests from playground code.
  Enforces SSRF protection (blocks private IPs), rate limiting (max calls per
  execution), request timeouts, and response body truncation.

  ## Usage in playground code

      alias Blackboex.Playgrounds.Http

      {:ok, resp} = Http.get("https://jsonplaceholder.typicode.com/users/1")
      IO.puts(resp.body)

      {:ok, resp} = Http.post("https://httpbin.org/post", Jason.encode!(%{key: "value"}),
        [{"content-type", "application/json"}])
  """

  @max_calls_per_execution 5
  @request_timeout 3_000
  @max_body_size 65_536

  @type response :: %{status: integer(), headers: map(), body: String.t()}

  @spec get(String.t(), [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, String.t()}
  def get(url, headers \\ []) do
    request(:get, url, nil, headers)
  end

  @spec post(String.t(), String.t() | nil, [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, String.t()}
  def post(url, body \\ nil, headers \\ []) do
    request(:post, url, body, headers)
  end

  @spec put(String.t(), String.t() | nil, [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, String.t()}
  def put(url, body \\ nil, headers \\ []) do
    request(:put, url, body, headers)
  end

  @spec patch(String.t(), String.t() | nil, [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, String.t()}
  def patch(url, body \\ nil, headers \\ []) do
    request(:patch, url, body, headers)
  end

  @spec delete(String.t(), [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, String.t()}
  def delete(url, headers \\ []) do
    request(:delete, url, nil, headers)
  end

  defp request(method, url, body, headers) do
    with :ok <- check_call_count(),
         :ok <- validate_url(url) do
      increment_call_count()
      do_request(method, url, body, headers)
    end
  end

  defp do_request(method, url, body, headers) do
    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: @request_timeout,
        connect_options: [timeout: @request_timeout],
        redirect: false,
        retry: false,
        cache: false,
        decode_body: false
      ]
      |> maybe_add_body(body)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        truncated_body = truncate_body(resp_body)
        headers_map = headers_to_map(resp_headers)
        {:ok, %{status: status, headers: headers_map, body: truncated_body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "request timed out after #{@request_timeout}ms"}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "connection error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "request failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "request failed: #{Exception.message(e)}"}
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :body, body)

  defp truncate_body(body) when is_binary(body) do
    if byte_size(body) > @max_body_size do
      binary_part(body, 0, @max_body_size)
    else
      body
    end
  end

  defp truncate_body(body), do: inspect(body)

  defp headers_to_map(headers) do
    Map.new(headers, fn {k, v} ->
      value = if is_list(v), do: Enum.join(v, ", "), else: v
      {k, value}
    end)
  end

  # ── Call count tracking (process dictionary) ─────────────────

  @call_count_key :playground_http_call_count

  defp check_call_count do
    count = Process.get(@call_count_key, 0)

    if count >= @max_calls_per_execution do
      {:error, "HTTP call limit exceeded: max #{@max_calls_per_execution} calls per execution"}
    else
      :ok
    end
  end

  defp increment_call_count do
    count = Process.get(@call_count_key, 0)
    Process.put(@call_count_key, count + 1)
  end

  # ── URL validation (SSRF protection) ─────────────────────────

  @private_ranges [
    # 10.0.0.0/8
    {10, 0, 0, 0, 10, 255, 255, 255},
    # 172.16.0.0/12
    {172, 16, 0, 0, 172, 31, 255, 255},
    # 192.168.0.0/16
    {192, 168, 0, 0, 192, 168, 255, 255},
    # 169.254.0.0/16 (link-local)
    {169, 254, 0, 0, 169, 254, 255, 255},
    # 127.0.0.0/8 (loopback)
    {127, 0, 0, 0, 127, 255, 255, 255}
  ]

  defp validate_url(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- validate_scheme(uri),
         :ok <- validate_host(uri) do
      :ok
    end
  end

  defp validate_url(_), do: {:error, "URL must be a string"}

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(_), do: {:error, "only http and https URLs are allowed"}

  defp validate_host(%URI{host: nil}), do: {:error, "URL must have a host"}

  defp validate_host(%URI{host: host}) do
    # Allow configured base URL host (for self-calls)
    base_host = get_base_host()

    if host == base_host do
      :ok
    else
      check_not_private_ip(host)
    end
  end

  defp get_base_host do
    base_url =
      Application.get_env(:blackboex, Blackboex.Playgrounds.Api, [])
      |> Keyword.get(:base_url, "http://localhost:4000")

    URI.parse(base_url).host
  end

  defp check_not_private_ip(host) do
    case resolve_host(host) do
      {:ok, ip_tuple} ->
        if private_ip?(ip_tuple) do
          {:error, "requests to private/internal networks are blocked"}
        else
          :ok
        end

      {:error, _} ->
        # If we can't resolve, allow it (DNS will fail at request time)
        :ok
    end
  end

  defp resolve_host(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _} ->
        case :inet.getaddr(String.to_charlist(host), :inet) do
          {:ok, ip} -> {:ok, ip}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp private_ip?({a, b, c, d}) do
    Enum.any?(@private_ranges, fn {a1, b1, c1, d1, a2, b2, c2, d2} ->
      {a, b, c, d} >= {a1, b1, c1, d1} and {a, b, c, d} <= {a2, b2, c2, d2}
    end)
  end

  defp private_ip?(_), do: false
end
