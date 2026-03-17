defmodule BlackboexWeb.Plugs.SetOrganization do
  @moduledoc """
  Plug that sets the current organization and membership on the scope.

  Loads the organization from the session `organization_id` key.
  If the org doesn't exist, the user lost membership, or no org_id is set,
  falls back to the user's first organization.
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
        org_id = get_session(conn, :organization_id)
        set_organization(conn, scope, user, org_id)

      _ ->
        conn
    end
  end

  defp set_organization(conn, scope, user, org_id) when is_binary(org_id) do
    with %{} = org <- Organizations.get_organization(org_id),
         %{} = membership <- Organizations.get_user_membership(org, user) do
      assign(conn, :current_scope, Scope.with_organization(scope, org, membership))
    else
      _ -> fallback_to_first_org(conn, scope, user)
    end
  end

  defp set_organization(conn, scope, user, _nil) do
    fallback_to_first_org(conn, scope, user)
  end

  defp fallback_to_first_org(conn, scope, user) do
    case Organizations.list_user_organizations(user) do
      [org | _] ->
        membership = Organizations.get_user_membership(org, user)

        if membership do
          assign(conn, :current_scope, Scope.with_organization(scope, org, membership))
        else
          conn
        end

      [] ->
        conn
    end
  end
end
