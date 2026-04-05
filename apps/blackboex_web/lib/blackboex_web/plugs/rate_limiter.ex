defmodule BlackboexWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting for published API requests.

  Applies 4 layers of rate limiting:
  1. Per IP: 100 req/min
  2. Per API key: 60 req/min (configurable per key)
  3. Per API (global): 1000 req/min
  4. Per endpoint: configurable

  Called inline from DynamicApiRouter, not as a Plug.
  """

  alias Blackboex.Telemetry.Events

  import Plug.Conn

  @ip_limit 100
  @ip_scale :timer.minutes(1)
  @default_key_limit 60
  @key_scale :timer.minutes(1)
  @api_global_limit 1000
  @api_scale :timer.minutes(1)
  @draft_ip_limit 20
  @draft_ip_scale :timer.minutes(1)

  @spec check_rate(Plug.Conn.t(), map()) ::
          {:ok, Plug.Conn.t()} | {:error, :rate_limited, non_neg_integer()}
  def check_rate(conn, metadata) do
    with {:ok, conn} <- check_ip_limit(conn),
         {:ok, conn} <- check_api_key_limit(conn),
         {:ok, conn} <- check_api_global_limit(conn, metadata) do
      {:ok, conn}
    end
  end

  @doc "Lighter rate limit for draft/compiled (non-published) APIs: IP-only at #{@draft_ip_limit} req/min."
  @spec check_rate_draft(Plug.Conn.t()) ::
          {:ok, Plug.Conn.t()} | {:error, :rate_limited, non_neg_integer()}
  def check_rate_draft(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case BlackboexWeb.RateLimiterBackend.hit(
           "draft_ip:#{ip}",
           @draft_ip_scale,
           @draft_ip_limit
         ) do
      {:allow, _count} ->
        {:ok, conn}

      {:deny, retry_after_ms} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        Events.emit_rate_limit_rejected(%{type: :draft, key: ip})
        {:error, :rate_limited, div(retry_after_ms, 1000)}
    end
  end

  defp check_ip_limit(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case BlackboexWeb.RateLimiterBackend.hit("ip:#{ip}", @ip_scale, @ip_limit) do
      {:allow, count} ->
        conn =
          conn
          |> put_resp_header("x-ratelimit-limit", to_string(@ip_limit))
          |> put_resp_header("x-ratelimit-remaining", to_string(max(@ip_limit - count, 0)))

        {:ok, conn}

      {:deny, retry_after_ms} ->
        Events.emit_rate_limit_rejected(%{type: :ip, key: ip})
        {:error, :rate_limited, div(retry_after_ms, 1000)}
    end
  end

  defp check_api_key_limit(conn) do
    case conn.assigns[:api_key] do
      nil ->
        {:ok, conn}

      api_key ->
        limit = api_key.rate_limit || @default_key_limit

        case BlackboexWeb.RateLimiterBackend.hit("key:#{api_key.id}", @key_scale, limit) do
          {:allow, _count} ->
            {:ok, conn}

          {:deny, retry_after_ms} ->
            Events.emit_rate_limit_rejected(%{type: :api_key, key: api_key.id})
            {:error, :rate_limited, div(retry_after_ms, 1000)}
        end
    end
  end

  defp check_api_global_limit(conn, metadata) do
    api_id = metadata.api_id

    case BlackboexWeb.RateLimiterBackend.hit("api:#{api_id}", @api_scale, @api_global_limit) do
      {:allow, _count} ->
        {:ok, conn}

      {:deny, retry_after_ms} ->
        Events.emit_rate_limit_rejected(%{type: :global, key: api_id})
        {:error, :rate_limited, div(retry_after_ms, 1000)}
    end
  end
end
