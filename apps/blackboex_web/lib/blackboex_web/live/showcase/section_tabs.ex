defmodule BlackboexWeb.Showcase.Sections.Tabs do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Tabs

  @code_tabs ~S"""
  <.tabs id="demo-tabs" default="tab1" :let={builder}>
    <.tabs_list>
      <.tabs_trigger builder={builder} value="tab1">Overview</.tabs_trigger>
      <.tabs_trigger builder={builder} value="tab2">Analytics</.tabs_trigger>
    </.tabs_list>
    <.tabs_content value="tab1">Overview content.</.tabs_content>
    <.tabs_content value="tab2">Analytics content.</.tabs_content>
  </.tabs>
  """

  def render(assigns) do
    assigns = assign(assigns, :code_tabs, @code_tabs)

    ~H"""
    <.section_header
      title="Tabs"
      description="ShadCN-style tabs with JS-driven active state. Requires an id and default value."
      module="BlackboexWeb.Components.Tabs"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Tabs" code={@code_tabs}>
        <.tabs :let={builder} id="showcase-tabs" default="tab1">
          <.tabs_list>
            <.tabs_trigger builder={builder} value="tab1">Overview</.tabs_trigger>
            <.tabs_trigger builder={builder} value="tab2">Analytics</.tabs_trigger>
            <.tabs_trigger builder={builder} value="tab3">Settings</.tabs_trigger>
          </.tabs_list>
          <.tabs_content value="tab1">
            <p class="text-sm text-muted-foreground p-4">Overview tab content goes here.</p>
          </.tabs_content>
          <.tabs_content value="tab2">
            <p class="text-sm text-muted-foreground p-4">Analytics tab content goes here.</p>
          </.tabs_content>
          <.tabs_content value="tab3">
            <p class="text-sm text-muted-foreground p-4">Settings tab content goes here.</p>
          </.tabs_content>
        </.tabs>
      </.showcase_block>
    </div>
    """
  end
end
