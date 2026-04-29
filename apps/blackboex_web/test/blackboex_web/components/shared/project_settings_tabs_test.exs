defmodule BlackboexWeb.Components.Shared.ProjectSettingsTabsTest do
  use BlackboexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BlackboexWeb.Components.Shared.ProjectSettingsTabs

  @moduletag :unit

  describe "project_settings_tabs/1" do
    test "renders all six tabs" do
      html =
        render_component(&project_settings_tabs/1,
          active: :dashboard,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      assert html =~ "Dashboard"
      assert html =~ "General"
      assert html =~ "Members"
      assert html =~ "API Keys"
      assert html =~ "Env Vars"
      assert html =~ "LLM Integrations"
    end

    test "marks active tab with aria-current='page'" do
      html =
        render_component(&project_settings_tabs/1,
          active: :env_vars,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      assert html =~ ~s(aria-current="page" data-tab="env_vars")
    end

    test "non-active tabs have no aria-current" do
      html =
        render_component(&project_settings_tabs/1,
          active: :env_vars,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      refute html =~ ~s(aria-current="page" data-tab="dashboard")
      refute html =~ ~s(aria-current="page" data-tab="general")
    end

    test "URLs are built with org_slug and project_slug" do
      html =
        render_component(&project_settings_tabs/1,
          active: :dashboard,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      assert html =~ "/orgs/acme/projects/my-proj"
      assert html =~ "/orgs/acme/projects/my-proj/settings"
      assert html =~ "/orgs/acme/projects/my-proj/members"
      assert html =~ "/orgs/acme/projects/my-proj/api-keys"
      assert html =~ "/orgs/acme/projects/my-proj/env-vars"
      assert html =~ "/orgs/acme/projects/my-proj/integrations"
    end

    test "only one tab is active at a time" do
      html =
        render_component(&project_settings_tabs/1,
          active: :api_keys,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      # Count occurrences of aria-current='page'
      count =
        html
        |> String.split(~s(aria-current="page"))
        |> length()
        |> Kernel.-(1)

      assert count == 1
    end

    test "renders container element with data-role" do
      html =
        render_component(&project_settings_tabs/1,
          active: :dashboard,
          org_slug: "acme",
          project_slug: "my-proj"
        )

      assert html =~ ~s(data-role="project-settings-tabs")
    end
  end
end
