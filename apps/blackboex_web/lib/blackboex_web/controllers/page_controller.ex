defmodule BlackboexWeb.PageController do
  use BlackboexWeb, :controller

  alias BlackboexWeb.LastVisited

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect_authenticated(conn, conn.assigns.current_scope.user)
    else
      render(conn, :home, page_title: "Describe it. We build the API.")
    end
  end

  @spec redirect_authenticated(Plug.Conn.t(), Blackboex.Accounts.User.t()) :: Plug.Conn.t()
  defp redirect_authenticated(conn, user) do
    case LastVisited.resolve(user) do
      {:ok, org, project} -> redirect(conn, to: "/orgs/#{org.slug}/projects/#{project.slug}")
      {:org_only, org} -> redirect(conn, to: "/orgs/#{org.slug}")
      :none -> render(conn, :home, page_title: "Describe it. We build the API.")
    end
  end
end
