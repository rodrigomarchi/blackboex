defmodule BlackboexWeb.PageController do
  use BlackboexWeb, :controller

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
    case Blackboex.Organizations.list_user_organizations(user) do
      [org | _] -> redirect_to_org(conn, org)
      [] -> render(conn, :home, page_title: "Describe it. We build the API.")
    end
  end

  @spec redirect_to_org(Plug.Conn.t(), Blackboex.Organizations.Organization.t()) ::
          Plug.Conn.t()
  defp redirect_to_org(conn, org) do
    case Blackboex.Projects.get_default_project(org.id) do
      nil -> redirect(conn, to: "/orgs/#{org.slug}")
      project -> redirect(conn, to: "/orgs/#{org.slug}/projects/#{project.slug}")
    end
  end
end
