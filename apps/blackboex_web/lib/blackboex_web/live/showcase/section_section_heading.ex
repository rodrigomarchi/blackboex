defmodule BlackboexWeb.Showcase.Sections.SectionHeading do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.SectionHeading

  def render(assigns) do
    ~H"""
    <.section_header
      title="Section Heading"
      description="Semantic heading component with levels, icon, description slot, actions slot, variant/tone, compact, icon_class, and heading_class."
      module="BlackboexWeb.Components.UI.SectionHeading"
    />
    <div class="space-y-10">
      <.showcase_block title="Levels">
        <div class="space-y-6">
          <.section_heading level="h1">Level h1 — Page Title</.section_heading>
          <.section_heading level="h2">Level h2 — Section (default)</.section_heading>
          <.section_heading level="h3">Level h3 — Subsection</.section_heading>
        </div>
      </.showcase_block>

      <.showcase_block title="With Icon">
        <.section_heading icon="hero-cog-6-tooth">Settings</.section_heading>
      </.showcase_block>

      <.showcase_block title="With Description">
        <.section_heading>
          API Keys
          <:description>Manage access tokens for this API.</:description>
        </.section_heading>
      </.showcase_block>

      <.showcase_block title="With Actions">
        <.section_heading>
          Members
          <:actions>
            <.button variant="primary" size="sm">Invite</.button>
          </:actions>
        </.section_heading>
      </.showcase_block>

      <.showcase_block title="Label Variant">
        <.section_heading variant="label">Sidebar Label</.section_heading>
      </.showcase_block>

      <.showcase_block title="Muted Tone">
        <.section_heading tone="muted">Muted Subheader</.section_heading>
      </.showcase_block>

      <.showcase_block title="Compact (no gap)">
        <div class="space-y-6">
          <div>
            <p class="text-xs text-muted-foreground mb-1">compact=false (default):</p>
            <.section_heading>
              Normal Heading
              <:description>There is a gap between heading and description.</:description>
            </.section_heading>
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">compact=true:</p>
            <.section_heading compact>
              Compact Heading
              <:description>No gap between heading and description.</:description>
            </.section_heading>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Custom icon_class">
        <div class="space-y-4">
          <.section_heading icon="hero-key" icon_class="size-4 text-accent-amber">
            API Keys (amber icon)
          </.section_heading>
          <.section_heading icon="hero-shield-check" icon_class="size-4 text-status-completed">
            Security (green icon)
          </.section_heading>
          <.section_heading icon="hero-exclamation-triangle" icon_class="size-4 text-destructive">
            Danger Zone (red icon)
          </.section_heading>
        </div>
      </.showcase_block>

      <.showcase_block title="Custom heading_class">
        <div class="space-y-4">
          <.section_heading heading_class="text-primary">
            Primary colored heading
          </.section_heading>
          <.section_heading heading_class="text-destructive italic">
            Destructive italic heading
          </.section_heading>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
