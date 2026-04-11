defmodule BlackboexWeb.Showcase.Sections.StatusDot do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.StatusDot

  @code_tone ~S"""
  <%!-- tone overrides the status-to-color mapping --%>
  <.status_dot status="custom" tone="active" />
  <.status_dot status="my-state" tone="failed" />
  <.status_dot status="unknown" tone="running" />
  """

  def render(assigns) do
    assigns = assign(assigns, :code_tone, @code_tone)

    ~H"""
    <.section_header
      title="Status Dot"
      description="Colored pill with leading dot for status displays. Auto-maps status strings to color palettes. Override with tone attr."
      module="BlackboexWeb.Components.UI.StatusDot"
    />
    <div class="space-y-10">
      <.showcase_block title="All Statuses">
        <div class="flex flex-wrap gap-3">
          <.status_dot status="active" />
          <.status_dot status="running" />
          <.status_dot status="pending" />
          <.status_dot status="draft" />
          <.status_dot status="paused" />
          <.status_dot status="failed" />
          <.status_dot status="error" />
          <.status_dot status="archived" />
          <.status_dot status="success" />
          <.status_dot status="completed" />
        </div>
      </.showcase_block>

      <.showcase_block title="Custom Label">
        <div class="flex gap-3">
          <.status_dot status="running" label="In progress" />
          <.status_dot status="active" label="Published" />
        </div>
      </.showcase_block>

      <.showcase_block title="With Pulse">
        <div class="flex gap-3">
          <.status_dot status="running" pulse />
          <.status_dot status="active" pulse />
        </div>
      </.showcase_block>

      <.showcase_block title="Tone Override" code={@code_tone}>
        <div class="flex flex-wrap gap-3">
          <.status_dot status="custom-status" tone="active" label="tone=active" />
          <.status_dot status="custom-status" tone="running" label="tone=running" />
          <.status_dot status="custom-status" tone="pending" label="tone=pending" />
          <.status_dot status="custom-status" tone="draft" label="tone=draft" />
          <.status_dot status="custom-status" tone="paused" label="tone=paused" />
          <.status_dot status="custom-status" tone="failed" label="tone=failed" />
          <.status_dot status="custom-status" tone="error" label="tone=error" />
          <.status_dot status="custom-status" tone="success" label="tone=success" />
        </div>
        <p class="mt-2 text-xs text-muted-foreground">
          The tone attr forces a specific color palette regardless of the status string.
          Unknown tones fall back to neutral muted styling.
        </p>
      </.showcase_block>
    </div>
    """
  end
end
