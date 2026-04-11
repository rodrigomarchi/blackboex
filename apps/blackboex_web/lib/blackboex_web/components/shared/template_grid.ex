defmodule BlackboexWeb.Components.Shared.TemplateGrid do
  @moduledoc """
  Selectable grid of template cards used in create modals.

  Renders each template via the `:card` slot so callers can customize the card body.
  """
  use BlackboexWeb, :html

  attr :templates, :list, required: true, doc: "flat list of templates to render"
  attr :selected, :any, default: nil, doc: "currently selected template (map with :id) or nil"
  attr :click_event, :string, default: "select_template"
  attr :class, :string, default: nil

  slot :card, required: true do
    attr :template, :any
  end

  @spec template_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def template_grid(assigns) do
    ~H"""
    <div class={["max-h-52 overflow-y-auto -mx-1 px-1", @class]}>
      <div class="grid grid-cols-2 gap-2">
        <.button
          :for={template <- @templates}
          type="button"
          variant="ghost"
          phx-click={@click_event}
          phx-value-id={template.id}
          class={[
            "h-auto w-auto justify-start flex items-start gap-2 rounded-lg border p-2.5 text-left transition-colors hover:border-primary/50 hover:bg-transparent",
            if(@selected && @selected.id == template.id,
              do: "border-primary bg-primary/5 ring-1 ring-primary",
              else: "border-border bg-background"
            )
          ]}
        >
          {render_slot(@card, template)}
        </.button>
      </div>
    </div>
    """
  end
end
