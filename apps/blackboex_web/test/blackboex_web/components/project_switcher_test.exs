defmodule BlackboexWeb.Components.Shared.ProjectSwitcherTest do
  @moduledoc """
  Tests for the ProjectSwitcher component.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import BlackboexWeb.Components.Shared.ProjectSwitcher

  @moduletag :unit

  defp org(overrides \\ %{}) do
    Map.merge(%{id: "org-1", name: "Acme Corp", slug: "acme"}, overrides)
  end

  defp project(overrides \\ %{}) do
    Map.merge(%{id: "proj-1", name: "Main Project", slug: "main"}, overrides)
  end

  describe "project_switcher/1" do
    test "renders org name" do
      html =
        render_component(&project_switcher/1,
          org: org(),
          project: nil,
          projects: []
        )

      assert html =~ "Acme Corp"
    end

    test "renders current project name" do
      html =
        render_component(&project_switcher/1,
          org: org(),
          project: project(),
          projects: []
        )

      assert html =~ "Main Project"
    end

    test "renders No Project when project is nil" do
      html =
        render_component(&project_switcher/1,
          org: org(),
          project: nil,
          projects: []
        )

      assert html =~ "No Project"
    end

    test "renders project list links" do
      projects = [
        project(%{id: "p1", name: "Alpha", slug: "alpha"}),
        project(%{id: "p2", name: "Beta", slug: "beta"})
      ]

      html =
        render_component(&project_switcher/1,
          org: org(),
          project: nil,
          projects: projects
        )

      assert html =~ "Alpha"
      assert html =~ "Beta"
      assert html =~ "/orgs/acme/projects/alpha"
      assert html =~ "/orgs/acme/projects/beta"
    end

    test "renders New project link when projects list is non-empty" do
      html =
        render_component(&project_switcher/1,
          org: org(),
          project: project(),
          projects: [project()]
        )

      assert html =~ "New project"
      assert html =~ "/orgs/acme/projects/new"
    end

    test "does not render nav when projects list is empty" do
      html =
        render_component(&project_switcher/1,
          org: org(),
          project: nil,
          projects: []
        )

      refute html =~ "New project"
    end

    test "highlights active project" do
      active = project(%{id: "p1", name: "Active", slug: "active"})
      other = project(%{id: "p2", name: "Other", slug: "other"})

      html =
        render_component(&project_switcher/1,
          org: org(),
          project: active,
          projects: [active, other]
        )

      assert html =~ "bg-muted font-medium"
    end
  end
end
