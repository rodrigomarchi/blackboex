defmodule BlackboexWeb.Showcase.Sections.DescriptionList do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.DescriptionList
  import BlackboexWeb.Components.Badge

  def render(assigns) do
    ~H"""
    <.section_header
      title="Description List"
      description="Grid of labeled key-value pairs. Used for detail views and API info panels."
      module="BlackboexWeb.Components.Shared.DescriptionList"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic">
        <.description_list>
          <:item label="Name">Weather API</:item>
          <:item label="Status">
            <.badge variant="success">Active</.badge>
          </:item>
          <:item label="Created">January 1, 2025</:item>
          <:item label="Owner">alice@example.com</:item>
          <:item label="Version">v2.1.0</:item>
          <:item label="Endpoint">/api/v1/weather</:item>
        </.description_list>
      </.showcase_block>
    </div>
    """
  end
end
