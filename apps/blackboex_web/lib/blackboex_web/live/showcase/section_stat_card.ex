defmodule BlackboexWeb.Showcase.Sections.StatCard do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.StatCard

  @code_href ~S"""
  <.stat_card label="APIs" value="8" icon="hero-cube" href={~p"/showcase/overview"} />
  """

  def render(assigns) do
    assigns = assign(assigns, :code_href, @code_href)

    ~H"""
    <.section_header
      title="Stat Card"
      description="Labeled metric card with optional icon, color, icon_class, and href link. Used in dashboard grids."
      module="BlackboexWeb.Components.Shared.StatCard"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic">
        <div class="grid grid-cols-3 gap-4">
          <.stat_card label="Total Requests" value="12,345" />
          <.stat_card label="Error Rate" value="5.2%" color="destructive" />
          <.stat_card label="Avg Latency" value="42ms" />
        </div>
      </.showcase_block>

      <.showcase_block title="With Icon">
        <div class="grid grid-cols-3 gap-4">
          <.stat_card label="APIs" value="8" icon="hero-cube" />
          <.stat_card label="Flows" value="3" icon="hero-arrow-path" />
          <.stat_card label="Keys" value="12" icon="hero-key" />
        </div>
      </.showcase_block>

      <.showcase_block title="With href (clickable link)" code={@code_href}>
        <div class="grid grid-cols-3 gap-4">
          <.stat_card label="APIs" value="8" icon="hero-cube" href={~p"/showcase/button"} />
          <.stat_card label="Flows" value="3" icon="hero-arrow-path" href={~p"/showcase/badge"} />
          <.stat_card label="Keys" value="12" icon="hero-key" href={~p"/showcase/card"} />
        </div>
        <p class="mt-2 text-xs text-muted-foreground">
          When href is set, the card renders as a &lt;.link navigate=...&gt; with hover border highlight.
        </p>
      </.showcase_block>

      <.showcase_block title="With icon_class">
        <div class="grid grid-cols-3 gap-4">
          <.stat_card
            label="Revenue"
            value="$4,200"
            icon="hero-currency-dollar"
            icon_class="text-status-completed"
          />
          <.stat_card
            label="Warnings"
            value="7"
            icon="hero-exclamation-triangle"
            icon_class="text-accent-amber"
          />
          <.stat_card label="Errors" value="2" icon="hero-x-circle" icon_class="text-destructive" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
