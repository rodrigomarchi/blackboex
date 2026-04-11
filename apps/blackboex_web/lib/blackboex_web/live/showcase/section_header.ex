defmodule BlackboexWeb.Showcase.Sections.PageHeader do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Header"
      description="Page header with title, optional subtitle, and action slots. Used at the top of every page."
      module="BlackboexWeb.Components.Header"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic">
        <.header>My APIs</.header>
      </.showcase_block>

      <.showcase_block title="With Subtitle">
        <.header>
          API Keys
          <:subtitle>Manage authentication tokens for your APIs.</:subtitle>
        </.header>
      </.showcase_block>

      <.showcase_block title="With Actions">
        <.header>
          Flows
          <:subtitle>Automate tasks with reusable flows.</:subtitle>
          <:actions>
            <.button variant="primary" size="sm">
              <.icon name="hero-plus" class="size-4" /> New Flow
            </.button>
          </:actions>
        </.header>
      </.showcase_block>
    </div>
    """
  end
end
