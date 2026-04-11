defmodule BlackboexWeb.FlowLive.Components.CreateFlowModal do
  @moduledoc """
  Create Flow modal component — template picker, mode toggle, and form.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Shared.CategoryPills
  import BlackboexWeb.Components.Shared.IconBadge
  import BlackboexWeb.Components.Shared.ModeToggle
  import BlackboexWeb.Components.Shared.TemplateGrid
  import BlackboexWeb.Components.UI.AlertBanner

  attr :show, :boolean, required: true
  attr :create_mode, :atom, required: true
  attr :selected_template, :map, default: nil
  attr :template_categories, :list, required: true
  attr :active_category, :string, default: nil
  attr :create_form, :map, required: true
  attr :create_error, :string, default: nil

  def create_flow_modal(assigns) do
    ~H"""
    <.modal show={@show} on_close="close_create_modal" title="Create Flow">
      <.alert_banner
        :if={@create_error}
        variant="destructive"
        icon="hero-exclamation-circle"
        class="mb-4"
      >
        {@create_error}
      </.alert_banner>

      <%!-- Mode Toggle --%>
      <.mode_toggle
        options={[
          {"template", "From template", "hero-squares-2x2"},
          {"blank", "Blank flow", "hero-document-plus"}
        ]}
        active={@create_mode}
        click_event="set_create_mode"
        class="mb-4"
      />

      <%!-- Template Picker --%>
      <div :if={@create_mode == :template} class="mb-4 space-y-3">
        <.category_pills categories={@template_categories} active={@active_category} />

        <.template_grid
          templates={
            for {cat, templates} <- @template_categories,
                cat == @active_category,
                template <- templates,
                do: template
          }
          selected={@selected_template}
        >
          <:card :let={template}>
            <.icon_badge icon={template.icon} color="primary" class="mt-0.5" />
            <div class="min-w-0">
              <p class="text-xs font-medium leading-snug">{template.name}</p>
              <p class="text-muted-caption line-clamp-2 leading-snug mt-0.5">
                {template.description}
              </p>
              <p class="text-xs text-muted-foreground/60 mt-1">
                {length(template.definition["nodes"])} nodes
              </p>
            </div>
          </:card>
        </.template_grid>

        <%!-- Helper text --%>
        <p :if={is_nil(@selected_template)} class="text-muted-caption">
          Select a template above, or switch to
          <.button
            type="button"
            variant="link"
            size="icon-xs"
            phx-click="set_create_mode"
            phx-value-mode="blank"
            class="underline hover:text-foreground"
          >
            blank flow
          </.button>
          to start from scratch.
        </p>
      </div>

      <.form for={%{}} as={:flow} phx-submit="create_flow" class="space-y-4">
        <.input
          type="text"
          name="name"
          value={@create_form[:name].value}
          label="Name *"
          required
          maxlength="200"
          placeholder="My Workflow"
          autofocus
        />

        <.input
          type="textarea"
          name="description"
          value={@create_form[:description].value}
          label="Description"
          rows="3"
          maxlength="10000"
          placeholder="What does this flow do?"
        />

        <div class="flex justify-end gap-3 pt-2">
          <.button type="button" variant="outline" phx-click="close_create_modal">
            Cancel
          </.button>
          <.button
            type="submit"
            variant="primary"
            disabled={@create_mode == :template && is_nil(@selected_template)}
          >
            <.icon name="hero-arrow-right" class="mr-2 size-4" /> Create & Edit
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end
end
