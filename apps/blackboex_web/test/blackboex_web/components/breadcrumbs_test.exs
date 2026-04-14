defmodule BlackboexWeb.Components.Shared.BreadcrumbsTest do
  @moduledoc """
  Tests for the Breadcrumbs component.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import BlackboexWeb.Components.Shared.Breadcrumbs

  @moduletag :unit

  describe "breadcrumbs/1" do
    test "renders all item labels" do
      html =
        render_component(&breadcrumbs/1,
          items: [
            %{label: "Acme", href: "/orgs/acme"},
            %{label: "Main Project", href: "/orgs/acme/projects/main"},
            %{label: "APIs"}
          ]
        )

      assert html =~ "Acme"
      assert html =~ "Main Project"
      assert html =~ "APIs"
    end

    test "renders separator icon between items" do
      html =
        render_component(&breadcrumbs/1,
          items: [
            %{label: "Acme", href: "/orgs/acme"},
            %{label: "Project", href: "/orgs/acme/projects/p"},
            %{label: "APIs"}
          ]
        )

      assert html =~ "hero-chevron-right"
    end

    test "renders last item without href (current page)" do
      html =
        render_component(&breadcrumbs/1,
          items: [
            %{label: "Acme", href: "/orgs/acme"},
            %{label: "APIs"}
          ]
        )

      assert html =~ "text-foreground font-medium"
    end

    test "renders items with links for non-current items" do
      html =
        render_component(&breadcrumbs/1,
          items: [
            %{label: "Acme", href: "/orgs/acme"},
            %{label: "APIs"}
          ]
        )

      assert html =~ "/orgs/acme"
      assert html =~ "hover:text-foreground"
    end

    test "renders single item without separator" do
      html =
        render_component(&breadcrumbs/1,
          items: [%{label: "Home"}]
        )

      assert html =~ "Home"
      refute html =~ "hero-chevron-right"
    end

    test "renders nav with aria-label Breadcrumb" do
      html =
        render_component(&breadcrumbs/1,
          items: [%{label: "Home"}]
        )

      assert html =~ ~s(aria-label="Breadcrumb")
    end
  end
end
