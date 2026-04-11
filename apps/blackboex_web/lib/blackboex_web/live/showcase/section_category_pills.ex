defmodule BlackboexWeb.Showcase.Sections.CategoryPills do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.CategoryPills

  @sample_categories [
    {"All", []},
    {"REST API", []},
    {"GraphQL", []},
    {"Webhook", []},
    {"LLM", []}
  ]

  def render(assigns) do
    assigns = assign(assigns, :categories, @sample_categories)

    ~H"""
    <.section_header
      title="Category Pills"
      description="Row of filter pills for switching between template categories. Used in create modals."
      module="BlackboexWeb.Components.Shared.CategoryPills"
    />
    <div class="space-y-10">
      <.showcase_block title="With Active">
        <.category_pills categories={@categories} active="All" click_event="noop" />
      </.showcase_block>

      <.showcase_block title="Different Active">
        <.category_pills categories={@categories} active="LLM" click_event="noop" />
      </.showcase_block>

      <.showcase_block title="No Active">
        <.category_pills categories={@categories} click_event="noop" />
      </.showcase_block>
    </div>
    """
  end
end
