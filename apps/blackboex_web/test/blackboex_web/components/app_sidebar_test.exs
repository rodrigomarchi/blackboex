defmodule BlackboexWeb.Components.AppSidebarTest do
  @moduledoc false

  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  import Phoenix.LiveViewTest
  import BlackboexWeb.Components.AppSidebar

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations

  describe "sidebar/1 (legacy v1 — tree flag off)" do
    setup :register_and_log_in_user
    setup :create_org

    test "does NOT render global 'API Keys' link", %{user: user, org: org} do
      membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

      html =
        render_component(&sidebar/1,
          id: "sb-test",
          current_scope: scope,
          current_path: "/orgs/#{org.slug}/dashboard",
          collapsed: false
        )

      refute html =~ "API Keys"
      refute html =~ "CONFIG"
    end
  end
end
