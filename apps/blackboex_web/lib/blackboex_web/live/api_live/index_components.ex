defmodule BlackboexWeb.ApiLive.IndexComponents do
  @moduledoc """
  Function components for the API index LiveView.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.CategoryPills
  import BlackboexWeb.Components.Shared.IconBadge
  import BlackboexWeb.Components.Shared.InlineCode
  import BlackboexWeb.Components.Shared.ModeToggle
  import BlackboexWeb.Components.Shared.TemplateGrid
  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Shared.DashboardHelpers, only: [format_latency: 1]
  import BlackboexWeb.Components.UI.AlertBanner

  # ── Generation Badge ─────────────────────────────────────────────────────

  attr :status, :string, required: true

  def generation_badge(assigns) do
    ~H"""
    <.badge
      variant="warning"
      size="xs"
      class="animate-pulse"
    >
      <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Generating...
    </.badge>
    """
  end

  # ── API Table ────────────────────────────────────────────────────────────

  attr :api_rows, :list, required: true
  attr :org_slug, :string, default: nil

  def api_table(assigns) do
    ~H"""
    <.table id="apis" rows={@api_rows}>
      <:col :let={row} label="API">
        <div class="flex items-center gap-3">
          <.icon_badge icon="hero-cube" color="accent-blue" />
          <div class="min-w-0">
            <.link
              navigate={~p"/apis/#{row.api.id}/edit"}
              class="font-medium text-sm hover:underline truncate block"
            >
              {row.api.name}
            </.link>
            <p :if={row.api.description} class="text-muted-caption truncate max-w-xs">
              {row.api.description}
            </p>
          </div>
        </div>
      </:col>
      <:col :let={row} label="Status">
        <div class="flex items-center gap-1.5">
          <.badge class={api_status_classes(row.api.status)}>{row.api.status}</.badge>
          <.generation_badge
            :if={row.api.generation_status in ~w(pending generating validating)}
            status={row.api.generation_status}
          />
        </div>
      </:col>
      <:col :let={row} label="Calls">
        <div class="flex items-center gap-1.5">
          <.icon name="hero-signal-mini" class="size-3.5 text-accent-sky" />
          <span class="text-xs font-mono">{row.calls_24h}</span>
        </div>
      </:col>
      <:col :let={row} label="Avg Latency">
        <div class="flex items-center gap-1.5">
          <.icon name="hero-clock-mini" class="size-3.5 text-accent-amber" />
          <span class="text-xs font-mono">{format_latency(row.avg_latency)}</span>
        </div>
      </:col>
      <:col :let={row} label="Errors">
        <div class="flex items-center gap-1.5">
          <.icon
            name="hero-exclamation-circle-mini"
            class={"size-3.5 #{if row.errors_24h > 0, do: "text-destructive", else: "text-muted-foreground/50"}"}
          />
          <span class={"text-xs font-mono #{if row.errors_24h > 0, do: "text-destructive", else: ""}"}>
            {row.errors_24h}
          </span>
        </div>
      </:col>
      <:col :let={row} label="Endpoint">
        <%= if row.api.status == "published" do %>
          <.inline_code class="text-2xs text-accent-emerald">
            POST /{@org_slug}/{row.api.slug}
          </.inline_code>
        <% else %>
          <span class="text-xs italic text-muted-foreground">—</span>
        <% end %>
      </:col>
      <:action :let={row}>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/apis/#{row.api.id}/edit"}
            class="inline-flex items-center link-primary"
          >
            <.icon name="hero-pencil-square-mini" class="mr-1 size-3" /> Edit
          </.link>
          <.button
            variant="link"
            size="icon-xs"
            phx-click="request_confirm"
            phx-value-action="delete"
            phx-value-id={row.api.id}
            class="text-xs text-destructive"
          >
            <.icon name="hero-trash-mini" class="mr-1 size-3" /> Delete
          </.button>
        </div>
      </:action>
    </.table>
    """
  end

  # ── Create API Modal ─────────────────────────────────────────────────────

  attr :show_create_modal, :boolean, required: true
  attr :create_error, :string, default: nil
  attr :creation_mode, :atom, required: true
  attr :create_form, :any, required: true
  attr :template_categories, :list, required: true
  attr :active_category, :string, default: nil
  attr :selected_template, :any, default: nil

  def create_modal(assigns) do
    ~H"""
    <.modal show={@show_create_modal} on_close="close_create_modal" title="Create API">
      <.alert_banner
        :if={@create_error}
        variant="destructive"
        icon="hero-exclamation-circle"
        class="mb-4"
      >
        {@create_error}
      </.alert_banner>

      <%!-- Mode toggle --%>
      <.mode_toggle
        options={[
          {"switch_to_template", "From template", "hero-squares-2x2"},
          {"switch_to_description", "Describe from scratch", "hero-sparkles"}
        ]}
        active={
          if @creation_mode == :template, do: "switch_to_template", else: "switch_to_description"
        }
        class="mb-4"
      />

      <.form for={%{}} as={:api} phx-submit="create_api" class="space-y-4">
        <.input
          type="text"
          name="name"
          value={@create_form[:name].value}
          label="Name *"
          required
          maxlength="200"
          placeholder="My API"
          autofocus
        />

        <%!-- Template mode --%>
        <%= if @creation_mode == :template do %>
          <%= if @template_categories == [] do %>
            <p class="text-muted-description">No templates available yet.</p>
          <% else %>
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
                <.icon name="hero-bolt" class="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                <div class="min-w-0">
                  <p class="text-xs font-medium leading-snug">{template.name}</p>
                  <p class="text-muted-caption line-clamp-2 leading-snug mt-0.5">
                    {template.description}
                  </p>
                </div>
              </:card>
            </.template_grid>

            <%!-- Selected template preview --%>
            <%= if @selected_template do %>
              <.alert_banner variant="primary">
                <div class="space-y-1">
                  <div class="flex items-center justify-between">
                    <p class="text-sm font-medium">{@selected_template.name}</p>
                    <.button
                      type="button"
                      variant="ghost-muted"
                      size="icon-xs"
                      phx-click="clear_template"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </.button>
                  </div>
                  <p class="text-muted-caption">{@selected_template.description}</p>
                  <div class="flex flex-wrap gap-1 pt-1">
                    <.inline_code>handler.ex</.inline_code>
                    <.inline_code>helpers.ex</.inline_code>
                    <.inline_code>request_schema.ex</.inline_code>
                    <.inline_code>response_schema.ex</.inline_code>
                    <.inline_code>handler_test.ex</.inline_code>
                    <.inline_code>README.md</.inline_code>
                  </div>
                </div>
              </.alert_banner>
            <% else %>
              <p class="text-muted-caption">
                Select a template above, or
                <.button
                  type="button"
                  variant="link"
                  size="icon-xs"
                  phx-click="switch_to_description"
                  class="underline hover:text-foreground"
                >
                  describe from scratch
                </.button>
                to generate with AI.
              </p>
            <% end %>
          <% end %>
        <% end %>

        <%!-- Description mode --%>
        <%= if @creation_mode == :description do %>
          <.input
            type="textarea"
            name="description"
            value={@create_form[:description].value}
            label="What should this API do?"
            rows="4"
            maxlength="10000"
            placeholder="An API that receives a list of products with prices and returns the total, average, and most expensive item."
          />
          <p class="text-muted-caption">
            Describe in natural language. Code will be generated automatically.
          </p>
        <% end %>

        <%!-- Hidden description field in template mode so form submission works --%>
        <.input :if={@creation_mode == :template} type="hidden" name="description" value="" />

        <div class="flex justify-end gap-3 pt-2">
          <.button type="button" variant="outline" phx-click="close_create_modal">
            Cancel
          </.button>
          <%= if @creation_mode == :template && @selected_template do %>
            <.button type="submit" variant="primary">
              <.icon name="hero-bolt" class="mr-2 size-4" /> Create from template
            </.button>
          <% else %>
            <.button type="submit" variant="primary">
              <.icon name="hero-arrow-right" class="mr-2 size-4" /> Create & Edit
            </.button>
          <% end %>
        </div>
      </.form>
    </.modal>
    """
  end
end
