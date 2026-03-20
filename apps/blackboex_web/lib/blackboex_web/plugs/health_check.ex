defmodule BlackboexWeb.Plugs.HealthCheck do
  @moduledoc """
  Health check plug providing liveness, readiness, and startup probes.

  Positioned FIRST in the endpoint plug pipeline so health checks work
  even if downstream plugs have errors.

  - `/health/live` — always 200 (process is alive)
  - `/health/ready` — 200 if DB + registry ok, 503 otherwise
  - `/health/startup` — 200 if DB reachable (lighter check for pod startup)
  """

  @behaviour Plug

  alias Ecto.Adapters.SQL

  require Logger

  import Plug.Conn

  @db_check_timeout 5_000

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: "/health/live"} = conn, _opts) do
    respond(conn, 200, %{status: "ok"})
  end

  def call(%Plug.Conn{request_path: "/health/ready"} = conn, _opts) do
    readiness_check(conn)
  end

  def call(%Plug.Conn{request_path: "/health/startup"} = conn, _opts) do
    checks = %{database: check_database()}
    all_ok? = checks.database == "ok"
    status = if all_ok?, do: 200, else: 503

    respond(conn, status, %{status: status_label(all_ok?), checks: checks})
  end

  def call(conn, _opts), do: conn

  @spec readiness_check(Plug.Conn.t()) :: Plug.Conn.t()
  defp readiness_check(conn) do
    checks = %{
      database: check_database(),
      registry: check_registry()
    }

    all_ok? = Enum.all?(Map.values(checks), &(&1 == "ok"))
    status = if all_ok?, do: 200, else: 503

    respond(conn, status, %{status: status_label(all_ok?), checks: checks})
  end

  @spec check_database() :: String.t()
  defp check_database do
    case SQL.query(Blackboex.Repo, "SELECT 1", [], timeout: @db_check_timeout) do
      {:ok, _} -> "ok"
      _ -> "unavailable"
    end
  rescue
    error ->
      Logger.warning("Health check database failure: #{Exception.message(error)}")
      "unavailable"
  end

  @spec check_registry() :: String.t()
  defp check_registry do
    case :ets.info(:api_registry) do
      :undefined -> "unavailable"
      _ -> "ok"
    end
  end

  @spec status_label(boolean()) :: String.t()
  defp status_label(true), do: "ok"
  defp status_label(false), do: "unavailable"

  @spec respond(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp respond(conn, status, body) do
    json = Jason.encode!(body)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json)
    |> halt()
  rescue
    _error ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, ~s|{"status":"error"}|)
      |> halt()
  end
end
