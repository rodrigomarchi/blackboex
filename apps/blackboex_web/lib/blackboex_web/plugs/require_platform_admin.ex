defmodule BlackboexWeb.Plugs.RequirePlatformAdmin do
  @moduledoc """
  Plug that requires the current user to be a platform admin.

  Must be placed after `fetch_current_scope_for_user` and
  `require_authenticated_user` in the pipeline.
  """

  import Plug.Conn
  import Phoenix.Controller

  use BlackboexWeb, :verified_routes

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns[:current_scope] do
      %{user: %{is_platform_admin: true}} ->
        conn

      _ ->
        conn
        |> put_flash(:error, "You are not authorized to access this page.")
        |> redirect(to: ~p"/dashboard")
        |> halt()
    end
  end
end
