defmodule BlackboexWeb.Components.Shared.ProjectSettingsTabs do
  @moduledoc """
  Shared tab navigation for project-scoped settings pages.

  Renders a horizontal tab bar with links to the six project-scope pages:
  Dashboard, General, Members, API Keys, Env Vars, LLM Integrations.

  Active tab is highlighted; inactive tabs render as navigate links
  scoped under `/orgs/:org_slug/projects/:project_slug/...`.
  """

  use BlackboexWeb, :html

  @tab_defs [
    {:dashboard, "Dashboard", "/settings"},
    {:general, "General", "/settings/general"},
    {:members, "Members", "/members"},
    {:api_keys, "API Keys", "/api-keys"},
    {:env_vars, "Env Vars", "/env-vars"},
    {:llm_integrations, "LLM Integrations", "/integrations"}
  ]

  @doc """
  Renders the project settings tab bar.

  ## Attrs

    * `active` - the currently active tab. One of `:dashboard`, `:general`,
      `:members`, `:api_keys`, `:env_vars`, `:llm_integrations`.
    * `org_slug` - organization slug used to build links.
    * `project_slug` - project slug used to build links.
  """
  attr :active, :atom, required: true
  attr :org_slug, :string, required: true
  attr :project_slug, :string, required: true

  @spec project_settings_tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def project_settings_tabs(assigns) do
    assigns = assign(assigns, :tabs, @tab_defs)

    ~H"""
    <nav class="mt-4 flex gap-1 border-b" data-role="project-settings-tabs">
      <.project_tab
        :for={{tab_id, label, suffix} <- @tabs}
        label={label}
        tab_id={tab_id}
        href={"/orgs/#{@org_slug}/projects/#{@project_slug}#{suffix}"}
        active={@active == tab_id}
      />
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :tab_id, :atom, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false

  defp project_tab(assigns) do
    ~H"""
    <.link
      navigate={@href}
      data-tab={@tab_id}
      aria-current={if @active, do: "page"}
      class={[
        "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
        if(@active,
          do: "border-primary text-foreground",
          else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end
end
