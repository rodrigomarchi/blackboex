defmodule BlackboexWeb.PageController do
  use BlackboexWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
