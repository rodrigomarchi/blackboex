defmodule BlackboexWeb.PageControllerTest do
  use BlackboexWeb.ConnCase

  test "GET / renders landing page when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Describe it. We build the API."
  end

  test "GET / redirects to org/project for authenticated user", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    [org | _] = Blackboex.Organizations.list_user_organizations(user)
    project = Blackboex.Projects.get_default_project(org.id)

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == "/orgs/#{org.slug}/projects/#{project.slug}"
  end
end
