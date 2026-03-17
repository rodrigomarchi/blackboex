defmodule BlackboexWeb.PageControllerTest do
  use BlackboexWeb.ConnCase

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/users/log-in"
  end

  test "GET / redirects to dashboard when authenticated", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == "/dashboard"
  end
end
