defmodule BlackboexWeb.PageController do
  use BlackboexWeb, :controller

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :home, page_title: "Describe it. We build the API.")
    end
  end
end
