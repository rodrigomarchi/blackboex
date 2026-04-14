defmodule BlackboexWeb.Plugs.SetProjectFromUrl do
  @moduledoc """
  Plug that sets the current project from the `:project_slug` URL param.

  Requires `SetOrganizationFromUrl` (or equivalent) to have run first so
  that `current_scope` already carries the organization and membership.

  - Returns 404 when the project slug is invalid.
  - Returns 403 when the user has no access to the project.
  - Org owners and admins get implicit access (project_membership = nil).
  """

  import Plug.Conn

  alias Blackboex.Accounts.Scope
  alias Blackboex.Projects

  @behaviour Plug

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns[:current_scope] do
      %Scope{organization: org, membership: membership} = scope
      when not is_nil(org) and not is_nil(membership) ->
        project_slug = conn.params["project_slug"]
        set_project(conn, scope, org, membership, project_slug)

      _ ->
        conn
    end
  end

  defp set_project(conn, scope, org, membership, project_slug) when is_binary(project_slug) do
    case Projects.get_project_by_slug(org.id, project_slug) do
      nil ->
        conn
        |> put_status(404)
        |> Phoenix.Controller.put_view(
          html: BlackboexWeb.ErrorHTML,
          json: BlackboexWeb.ErrorJSON
        )
        |> Phoenix.Controller.render(:"404")
        |> halt()

      project ->
        resolve_access(conn, scope, membership, project)
    end
  end

  defp set_project(conn, _scope, _org, _membership, _nil), do: conn

  defp resolve_access(conn, scope, membership, project) do
    if membership.role in [:owner, :admin] do
      assign(conn, :current_scope, Scope.with_project(scope, project, nil))
    else
      user = scope.user

      case Projects.get_project_membership(project, user) do
        nil ->
          conn
          |> put_status(403)
          |> Phoenix.Controller.put_view(
            html: BlackboexWeb.ErrorHTML,
            json: BlackboexWeb.ErrorJSON
          )
          |> Phoenix.Controller.render(:"403")
          |> halt()

        project_membership ->
          assign(conn, :current_scope, Scope.with_project(scope, project, project_membership))
      end
    end
  end
end
