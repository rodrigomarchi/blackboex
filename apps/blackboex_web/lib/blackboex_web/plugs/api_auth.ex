defmodule BlackboexWeb.Plugs.ApiAuth do
  @moduledoc """
  Authentication for published API requests.

  Extracts API key from Authorization header (Bearer or X-API-Key),
  verifies it, and assigns the api_key to the connection.

  Called inline from DynamicApiRouter, not as a Plug.
  """

  import Plug.Conn

  alias Blackboex.Apis.Keys

  @spec authenticate(Plug.Conn.t(), map(), map()) ::
          {:ok, Plug.Conn.t()} | {:error, :missing_key | :invalid | :revoked | :expired}
  def authenticate(conn, api, metadata) do
    if skip_auth?(api, metadata) do
      {:ok, conn}
    else
      do_authenticate(conn, metadata)
    end
  end

  defp skip_auth?(_api, %{requires_auth: false}), do: true
  defp skip_auth?(%{status: status}, _metadata) when status != "published", do: true
  defp skip_auth?(_api, _metadata), do: false

  defp do_authenticate(conn, metadata) do
    case extract_key(conn) do
      {:ok, plain_key} ->
        case Keys.verify_key_for_api(plain_key, metadata.api_id) do
          {:ok, api_key} ->
            Keys.touch_last_used(api_key)
            {:ok, assign(conn, :api_key, api_key)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :missing_key} ->
        {:error, :missing_key}
    end
  end

  defp extract_key(conn) do
    with :miss <- extract_bearer(conn),
         :miss <- extract_x_api_key(conn) do
      {:error, :missing_key}
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> {:ok, String.trim(key)}
      _ -> :miss
    end
  end

  defp extract_x_api_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [key] when key != "" -> {:ok, String.trim(key)}
      _ -> :miss
    end
  end
end
