defmodule BlackboexWeb.Plugs.SetOrganizationFromUrl do
  @moduledoc """
  Plug that sets the current organization from the `:org_slug` URL param.

  Used in new `/orgs/:org_slug/*` routes. Returns 404 if the org slug is
  invalid or the user has no membership in that org.
  """

  import Plug.Conn

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations

  @behaviour Plug

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns[:current_scope] do
      %Scope{user: user} = scope when not is_nil(user) ->
        org_slug = conn.params["org_slug"]
        set_organization_from_slug(conn, scope, user, org_slug)

      _ ->
        conn
    end
  end

  defp set_organization_from_slug(conn, scope, user, org_slug) when is_binary(org_slug) do
    with %{} = org <- Organizations.get_organization_by_slug(org_slug),
         %{} = membership <- Organizations.get_user_membership(org, user) do
      assign(conn, :current_scope, Scope.with_organization(scope, org, membership))
    else
      _ ->
        conn
        |> put_status(404)
        |> Phoenix.Controller.put_view(
          html: BlackboexWeb.ErrorHTML,
          json: BlackboexWeb.ErrorJSON
        )
        |> Phoenix.Controller.render(:"404")
        |> halt()
    end
  end

  defp set_organization_from_slug(conn, _scope, _user, _nil), do: conn
end
