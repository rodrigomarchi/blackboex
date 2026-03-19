defmodule BlackboexWeb.PublicApiController do
  use BlackboexWeb, :controller

  alias Blackboex.Apis.Api
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo

  import Ecto.Query, warn: false

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"org_slug" => org_slug, "api_slug" => api_slug}) do
    with %Organization{} = org <- Repo.get_by(Organization, slug: org_slug),
         %Api{status: "published", visibility: "public"} = api <-
           Repo.get_by(Api, slug: api_slug, organization_id: org.id, status: "published") do
      render(conn, :show,
        api: api,
        org: org,
        api_url: api_url(conn, org_slug, api_slug)
      )
    else
      _ ->
        conn
        |> put_status(404)
        |> put_view(BlackboexWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp api_url(conn, org_slug, api_slug) do
    "#{conn.scheme}://#{conn.host}:#{conn.port}/api/#{org_slug}/#{api_slug}"
  end
end
