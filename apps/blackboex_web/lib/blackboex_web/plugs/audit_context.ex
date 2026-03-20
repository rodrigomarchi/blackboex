defmodule BlackboexWeb.Plugs.AuditContext do
  @moduledoc """
  Plug that injects the current user into ExAudit's process-level
  tracking data, so that row-level audits include the actor.
  """

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]

    if scope && scope.user do
      ip = conn.remote_ip |> :inet.ntoa() |> to_string()
      Blackboex.Audit.track(actor_id: scope.user.id, ip_address: ip)
    end

    conn
  end
end
