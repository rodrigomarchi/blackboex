defmodule BlackboexWeb.Components.Shared.DashboardNav do
  @moduledoc """
  Tab navigation for dashboard pages.

  Renders a horizontal pill bar with links to each dashboard section
  (Overview, APIs, Flows, LLM, Usage). Each tab uses `<.link navigate=...>`
  so switching tabs unmounts the current LiveView and mounts the target one
  (no parallel queries across tabs).
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :active, :atom,
    required: true,
    values: [:overview, :apis, :flows, :llm, :usage]

  attr :base_path, :string, required: true

  @tabs [
    %{suffix: "", key: :overview, label: "Overview", icon: "hero-home"},
    %{suffix: "/apis", key: :apis, label: "APIs", icon: "hero-cube"},
    %{suffix: "/flows", key: :flows, label: "Flows", icon: "hero-arrow-path"},
    %{suffix: "/llm", key: :llm, label: "LLM", icon: "hero-sparkles"},
    %{suffix: "/usage", key: :usage, label: "Usage", icon: "hero-chart-bar"}
  ]

  @spec dashboard_nav(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard_nav(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="inline-flex h-10 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground">
      <.link
        :for={tab <- @tabs}
        navigate={@base_path <> tab.suffix}
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
