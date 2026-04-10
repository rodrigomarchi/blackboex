defmodule BlackboexWeb.Components.Shared.DashboardNav do
  @moduledoc """
  Tab navigation for the dashboard pages.
  Renders a horizontal tab bar with links to each dashboard section.
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :active, :string, required: true

  @tabs [
    %{path: "/dashboard", key: "overview", label: "Overview", icon: "hero-home"},
    %{path: "/dashboard/apis", key: "apis", label: "APIs", icon: "hero-cube"},
    %{path: "/dashboard/flows", key: "flows", label: "Flows", icon: "hero-arrow-path"},
    %{path: "/dashboard/usage", key: "usage", label: "Usage", icon: "hero-chart-bar"},
    %{path: "/dashboard/llm", key: "llm", label: "LLM", icon: "hero-sparkles"}
  ]

  def dashboard_nav(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="inline-flex h-10 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground">
      <.link
        :for={tab <- @tabs}
        navigate={tab.path}
        class={[
          "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
          if(@active == tab.key,
            do: "bg-background text-foreground shadow-sm",
            else: "hover:bg-background/50"
          )
        ]}
      >
        <.icon name={tab.icon} class="size-3.5" />
        {tab.label}
      </.link>
    </div>
    """
  end
end
