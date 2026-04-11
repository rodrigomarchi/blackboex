defmodule BlackboexWeb.Showcase.Sections.TemplateGrid do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.TemplateGrid

  @templates [
    %{id: "1", name: "REST API", description: "Standard REST endpoint"},
    %{id: "2", name: "Webhook", description: "Incoming webhook handler"},
    %{id: "3", name: "GraphQL", description: "GraphQL query endpoint"},
    %{id: "4", name: "gRPC", description: "gRPC service wrapper"}
  ]

  @code_basic ~S"""
  <.template_grid templates={@templates}>
    <:card :let={t}>
      <span class="font-medium text-sm">{t.name}</span>
      <span class="text-xs text-muted-foreground">{t.description}</span>
    </:card>
  </.template_grid>
  """

  @code_selection ~S"""
  <.template_grid templates={@templates} selected={@selected_template}>
    <:card :let={t}>
      <span class="font-medium text-sm">{t.name}</span>
      <span class="text-xs text-muted-foreground">{t.description}</span>
    </:card>
  </.template_grid>
  """

  @code_custom_card ~S"""
  <.template_grid templates={@templates} selected={@selected}>
    <:card :let={t}>
      <div class="flex items-start gap-2 w-full">
        <.icon name="hero-cube" class="size-4 mt-0.5 shrink-0 text-primary" />
        <div>
          <p class="font-semibold text-sm">{t.name}</p>
          <p class="text-xs text-muted-foreground leading-tight">{t.description}</p>
        </div>
      </div>
    </:card>
  </.template_grid>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(templates: @templates, selected: nil, selected_one: hd(@templates))
      |> assign(:code_basic, @code_basic)
      |> assign(:code_selection, @code_selection)
      |> assign(:code_custom_card, @code_custom_card)

    ~H"""
    <.section_header
      title="Template Grid"
      description="Grid of selectable template cards. Renders templates in a responsive grid; the card slot renders each individual template card. selected= highlights the active selection."
      module="BlackboexWeb.Components.Shared.TemplateGrid"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Grid" code={@code_basic}>
        <.template_grid templates={@templates}>
          <:card :let={t}>
            <div class="flex flex-col gap-0.5">
              <span class="font-medium text-sm">{t.name}</span>
              <span class="text-xs text-muted-foreground">{t.description}</span>
            </div>
          </:card>
        </.template_grid>
      </.showcase_block>

      <.showcase_block title="With Selection" code={@code_selection}>
        <.template_grid templates={@templates} selected={@selected_one}>
          <:card :let={t}>
            <div class="flex flex-col gap-0.5">
              <span class="font-medium text-sm">{t.name}</span>
              <span class="text-xs text-muted-foreground">{t.description}</span>
            </div>
          </:card>
        </.template_grid>
        <p class="mt-2 text-xs text-muted-foreground">
          The first template (REST API) is shown selected via <code>selected={@selected_one}</code>.
        </p>
      </.showcase_block>

      <.showcase_block title="Custom Card Slot" code={@code_custom_card}>
        <.template_grid templates={@templates} selected={@selected}>
          <:card :let={t}>
            <div class="flex items-start gap-2 w-full">
              <.icon name="hero-cube" class="size-4 mt-0.5 shrink-0 text-primary" />
              <div>
                <p class="font-semibold text-sm">{t.name}</p>
                <p class="text-xs text-muted-foreground leading-tight">{t.description}</p>
              </div>
            </div>
          </:card>
        </.template_grid>
      </.showcase_block>
    </div>
    """
  end
end
