defmodule Blackboex.Testing.RequestExecutor do
  @moduledoc """
  Executes HTTP requests against user APIs with SSRF protection.

  Only allows requests to paths matching `/api/{username}/{slug}/*`.
  """

  @allowed_path_pattern ~r|^/api/[^/]+/[^/]+|
  @default_timeout 30_000

  @spec execute(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def execute(request, opts \\ []) do
    with :ok <- validate_url(request.url) do
      do_execute(request, opts)
    end
  end

  defp validate_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != nil -> {:error, :forbidden}
      uri.host != nil -> {:error, :forbidden}
      not Regex.match?(@allowed_path_pattern, url) -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp do_execute(request, opts) do
    timeout = Keyword.get(opts, :receive_timeout, @default_timeout)

    base_url = Keyword.get(opts, :base_url)

    url =
      if base_url do
        base_url <> request.url
      else
        request.url
      end

    req_opts =
      [
        method: request.method,
        url: url,
        headers: request.headers || [],
        receive_timeout: timeout,
        decode_body: false,
        retry: false
      ]
      |> maybe_add_body(request.body)
      |> maybe_add_plug(opts)

    {duration_us, result} = :timer.tc(fn -> Req.request(Req.new(req_opts)) end)
    duration_ms = div(duration_us, 1_000)

    case result do
      {:ok, %Req.Response{} = resp} ->
        {:ok,
         %{
           status: resp.status,
           headers: headers_to_map(resp.headers),
           body: resp.body || "",
           duration_ms: duration_ms
         }}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _reason} ->
        {:error, :connection_error}
    end
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, ""), do: opts
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :body, body)

  defp maybe_add_plug(opts, kw_opts) do
    case Keyword.get(kw_opts, :plug) do
      nil -> opts
      plug -> Keyword.put(opts, :plug, plug)
    end
  end

  defp headers_to_map(headers) when is_list(headers) do
    Map.new(headers, fn
      {key, values} when is_list(values) -> {key, Enum.join(values, ", ")}
      {key, value} -> {key, value}
    end)
  end

  defp headers_to_map(headers) when is_map(headers), do: headers
  defp headers_to_map(_headers), do: %{}
end
