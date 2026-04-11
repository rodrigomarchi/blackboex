defmodule BlackboexWeb.Showcase.Sections.StatChip do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.StatChip

  @code_basic ~S"""
  <.stat_chip label="Duration" value="1.2s" />
  <.stat_chip label="Requests" value="42" />
  <.stat_chip label="Status" value="Active" />
  """

  @code_with_icon ~S"""
  <.stat_chip icon="hero-clock" label="Duration" value="1.2s" />
  <.stat_chip icon="hero-squares-2x2" icon_class="text-accent-violet" label="Nodes" value="5" />
  <.stat_chip icon="hero-bolt" icon_class="text-accent-amber" label="Runs" value="128" />
  <.stat_chip icon="hero-x-circle" icon_class="text-destructive" label="Errors" value="3" />
  """

  @code_row ~S"""
  <div class="flex items-center gap-2">
    <.stat_chip icon="hero-clock" label="Latency" value="42ms" />
    <.stat_chip icon="hero-arrow-up-circle" icon_class="text-status-completed" label="Success" value="99.8%" />
    <.stat_chip icon="hero-cpu-chip" label="Tokens" value="2,400" />
    <.stat_chip icon="hero-calendar" label="Last run" value="2h ago" />
  </div>
  """

  @code_sizes ~S"""
  <.stat_chip label="Normal" value="default" />
  <.stat_chip label="Smaller padding" value="compact" class="px-2 py-1" />
  <.stat_chip label="Highlighted" value="active" class="border-primary bg-primary/5 text-primary" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_with_icon, @code_with_icon)
      |> assign(:code_row, @code_row)
      |> assign(:code_sizes, @code_sizes)

    ~H"""
    <.section_header
      title="Stat Chip"
      description="Compact inline stat chip — smaller than StatCard, used for ancillary metrics in sidebars, list rows, or compact panels. Shows label and value with optional icon."
      module="BlackboexWeb.Components.Shared.StatChip"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic" code={@code_basic}>
        <div class="flex flex-wrap gap-2">
          <.stat_chip label="Duration" value="1.2s" />
          <.stat_chip label="Requests" value="42" />
          <.stat_chip label="Status" value="Active" />
        </div>
      </.showcase_block>

      <.showcase_block title="With Icon" code={@code_with_icon}>
        <div class="flex flex-wrap gap-2">
          <.stat_chip icon="hero-clock" label="Duration" value="1.2s" />
          <.stat_chip
            icon="hero-squares-2x2"
            icon_class="text-accent-violet"
            label="Nodes"
            value="5"
          />
          <.stat_chip icon="hero-bolt" icon_class="text-accent-amber" label="Runs" value="128" />
          <.stat_chip
            icon="hero-x-circle"
            icon_class="text-destructive"
            label="Errors"
            value="3"
          />
        </div>
      </.showcase_block>

      <.showcase_block title="Multiple in a Row" code={@code_row}>
        <div class="flex items-center flex-wrap gap-2">
          <.stat_chip icon="hero-clock" label="Latency" value="42ms" />
          <.stat_chip
            icon="hero-arrow-up-circle"
            icon_class="text-status-completed"
            label="Success"
            value="99.8%"
          />
          <.stat_chip icon="hero-cpu-chip" label="Tokens" value="2,400" />
          <.stat_chip icon="hero-calendar" label="Last run" value="2h ago" />
        </div>
      </.showcase_block>

      <.showcase_block title="Sizes via class" code={@code_sizes}>
        <div class="flex flex-wrap gap-2 items-center">
          <.stat_chip label="Normal" value="default" />
          <.stat_chip label="Smaller padding" value="compact" class="px-2 py-1" />
          <.stat_chip
            label="Highlighted"
            value="active"
            class="border-primary bg-primary/5 text-primary"
          />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
