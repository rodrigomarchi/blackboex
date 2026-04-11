defmodule BlackboexWeb.FlowLive.Components.CreateFlowModal do
  @moduledoc """
  Create Flow modal component — template picker, mode toggle, and form.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Modal
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
      <div class="flex gap-1 rounded-lg bg-muted p-1 mb-4">
        <.button
          type="button"
          variant="ghost"
          phx-click="set_create_mode"
          phx-value-mode="template"
          class={[
            "h-auto flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-transparent",
            if(@create_mode == :template,
              do: "bg-background text-foreground shadow-sm",
              else: "text-muted-foreground hover:text-foreground"
            )
          ]}
        >
          <.icon name="hero-squares-2x2" class="mr-1.5 size-4 inline" /> From template
        </.button>
        <.button
          type="button"
          variant="ghost"
          phx-click="set_create_mode"
          phx-value-mode="blank"
          class={[
            "h-auto flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-transparent",
            if(@create_mode == :blank,
              do: "bg-background text-foreground shadow-sm",
              else: "text-muted-foreground hover:text-foreground"
            )
          ]}
        >
          <.icon name="hero-document-plus" class="mr-1.5 size-4 inline" /> Blank flow
        </.button>
      </div>

      <%!-- Template Picker --%>
      <div :if={@create_mode == :template} class="mb-4 space-y-3">
        <%!-- Category Pills --%>
        <div class="flex gap-1 flex-wrap">
          <%= for {cat, _templates} <- @template_categories do %>
            <.button
              type="button"
              variant="ghost"
              phx-click="set_active_category"
              phx-value-category={cat}
              class={[
                "h-auto w-auto rounded-full px-3 py-1 text-xs font-medium transition-colors border hover:bg-transparent",
                if(@active_category == cat,
                  do: "bg-primary text-primary-foreground border-primary",
                  else:
                    "bg-background text-muted-foreground border-border hover:border-primary/50 hover:text-foreground"
                )
              ]}
            >
              {cat}
            </.button>
          <% end %>
        </div>

        <%!-- Template Grid --%>
        <div class="max-h-52 overflow-y-auto -mx-1 px-1">
          <div class="grid grid-cols-2 gap-2">
            <%= for {cat, templates} <- @template_categories, cat == @active_category, template <- templates do %>
              <.button
                type="button"
                variant="ghost"
                phx-click="select_template"
                phx-value-id={template.id}
                class={[
                  "h-auto w-auto justify-start flex items-start gap-2 rounded-lg border p-2.5 text-left transition-colors hover:border-primary/50 hover:bg-transparent",
                  if(@selected_template && @selected_template.id == template.id,
                    do: "border-primary bg-primary/5 ring-1 ring-primary",
                    else: "border-border bg-background"
                  )
                ]}
              >
                <div class="flex size-8 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary mt-0.5">
                  <.icon name={template.icon} class="size-4" />
                </div>
                <div class="min-w-0">
                  <p class="text-xs font-medium leading-snug">{template.name}</p>
                  <p class="text-xs text-muted-foreground line-clamp-2 leading-snug mt-0.5">
                    {template.description}
                  </p>
                  <p class="text-xs text-muted-foreground/60 mt-1">
                    {length(template.definition["nodes"])} nodes
                  </p>
                </div>
              </.button>
            <% end %>
          </div>
        </div>

        <%!-- Helper text --%>
        <p :if={is_nil(@selected_template)} class="text-xs text-muted-foreground">
          Select a template above, or switch to
          <.button
            type="button"
            variant="ghost"
            phx-click="set_create_mode"
            phx-value-mode="blank"
            class="h-auto w-auto p-0 underline hover:text-foreground hover:bg-transparent"
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
