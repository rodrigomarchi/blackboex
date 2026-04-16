defmodule Blackboex.Playgrounds.Api do
  @moduledoc """
  Convenience wrappers to invoke project APIs and flows from playground code.

  Uses `Blackboex.Playgrounds.Http` internally, so all SSRF protections,
  rate limits, and timeouts apply.

  The base URL is configured via:

      config :blackboex, Blackboex.Playgrounds.Api, base_url: "http://localhost:4000"

  Override in production via `PLAYGROUND_BASE_URL` env var in `runtime.exs`.

  ## Usage in playground code

      alias Blackboex.Playgrounds.Api

      # Call a flow by its webhook token
      {:ok, result} = Api.call_flow("abc123token", %{"name" => "Alice"})

      # Call a project API
      {:ok, result} = Api.call_api("my-org", "my-project", "my-api", %{"key" => "val"}, "api-key-here")
  """

  alias Blackboex.Playgrounds.Http

  @spec call_flow(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def call_flow(webhook_token, input \\ %{}) when is_binary(webhook_token) do
    url = "#{base_url()}/webhook/#{webhook_token}"

    case Http.post(url, Jason.encode!(input), [{"content-type", "application/json"}]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, decode_body(body)}

      {:ok, %{status: status, body: body}} ->
        decoded = decode_body(body)
        error_msg = extract_error(decoded, status)
        {:error, error_msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec call_api(String.t(), String.t(), String.t(), map(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def call_api(org_slug, project_slug, api_slug, params \\ %{}, api_key)
      when is_binary(org_slug) and is_binary(project_slug) and is_binary(api_slug) and
             is_binary(api_key) do
    url = "#{base_url()}/api/#{org_slug}/#{project_slug}/#{api_slug}"

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{api_key}"}
    ]

    case Http.post(url, Jason.encode!(params), headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, decode_body(body)}

      {:ok, %{status: status, body: body}} ->
        decoded = decode_body(body)
        error_msg = extract_error(decoded, status)
        {:error, error_msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:blackboex, __MODULE__, [])
    |> Keyword.get(:base_url, "http://localhost:4000")
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"raw" => body}
    end
  end

  defp extract_error(%{"error" => error}, _status) when is_binary(error), do: error
  defp extract_error(decoded, status), do: "HTTP #{status}: #{inspect(decoded)}"
end
