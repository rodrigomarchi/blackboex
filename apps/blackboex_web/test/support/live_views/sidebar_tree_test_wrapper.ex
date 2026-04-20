defmodule BlackboexWeb.Components.SidebarTreeTestWrapper do
  @moduledoc false
  use BlackboexWeb, :live_view

  alias Blackboex.{Accounts, Organizations}
  alias Blackboex.Accounts.Scope

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    org = Organizations.get_organization!(session["org_id"])
    membership = Organizations.get_user_membership(org, user)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    {:ok, assign(socket, current_scope: scope, current_path: "/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={BlackboexWeb.Components.SidebarTreeComponent}
      id="test-sidebar-tree"
      current_scope={@current_scope}
      current_path={@current_path}
      collapsed={false}
    />
    """
  end
end
