defmodule BlackboexWeb.ApiLive.IndexComponents do
  @moduledoc """
  Function components for the API index LiveView.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Shared.DashboardHelpers, only: [format_latency: 1]
  import BlackboexWeb.Components.UI.AlertBanner

  # ── Generation Badge ─────────────────────────────────────────────────────

  attr :status, :string, required: true

  def generation_badge(assigns) do
    ~H"""
    <.badge
      variant="status"
      size="xs"
      class="border border-warning/30 bg-warning/10 text-warning-foreground animate-pulse"
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
          <div class="flex size-8 items-center justify-center rounded-lg bg-accent-blue/15">
            <.icon name="hero-cube" class="size-4 text-accent-blue" />
          </div>
          <div class="min-w-0">
            <.link
              navigate={~p"/apis/#{row.api.id}/edit"}
              class="font-medium text-sm hover:underline truncate block"
            >
              {row.api.name}
            </.link>
            <p :if={row.api.description} class="text-xs text-muted-foreground truncate max-w-xs">
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
          <code class="rounded bg-muted px-1.5 py-0.5 text-micro font-mono text-accent-emerald">
            POST /{@org_slug}/{row.api.slug}
          </code>
        <% else %>
          <span class="text-xs italic text-muted-foreground">—</span>
        <% end %>
      </:col>
      <:action :let={row}>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/apis/#{row.api.id}/edit"}
            class="inline-flex items-center text-xs text-primary hover:underline"
          >
            <.icon name="hero-pencil-square-mini" class="mr-1 size-3" /> Edit
          </.link>
          <.button
            variant="ghost"
            phx-click="request_confirm"
            phx-value-action="delete"
            phx-value-id={row.api.id}
            class="h-auto w-auto p-0 inline-flex items-center text-xs text-destructive hover:underline hover:bg-transparent"
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
      <div class="flex gap-1 rounded-lg bg-muted p-1 mb-4">
        <.button
          type="button"
          variant="ghost"
          phx-click="switch_to_template"
          class={[
            "h-auto flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-transparent",
            if(@creation_mode == :template,
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
          phx-click="switch_to_description"
          class={[
            "h-auto flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-transparent",
            if(@creation_mode == :description,
              do: "bg-background text-foreground shadow-sm",
              else: "text-muted-foreground hover:text-foreground"
            )
          ]}
        >
          <.icon name="hero-sparkles" class="mr-1.5 size-4 inline" /> Describe from scratch
        </.button>
      </div>

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
            <p class="text-sm text-muted-foreground">No templates available yet.</p>
          <% else %>
            <%!-- Category tabs --%>
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

            <%!-- Template grid --%>
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
                    <.icon name="hero-bolt" class="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                    <div class="min-w-0">
                      <p class="text-xs font-medium leading-snug">{template.name}</p>
                      <p class="text-xs text-muted-foreground line-clamp-2 leading-snug mt-0.5">
                        {template.description}
                      </p>
                    </div>
                  </.button>
                <% end %>
              </div>
            </div>

            <%!-- Selected template preview --%>
            <%= if @selected_template do %>
              <div class="rounded-lg border border-primary/30 bg-primary/5 p-3 space-y-1">
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
                <p class="text-xs text-muted-foreground">{@selected_template.description}</p>
                <div class="flex flex-wrap gap-1 pt-1">
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">handler.ex</span>
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">helpers.ex</span>
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                    request_schema.ex
                  </span>
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                    response_schema.ex
                  </span>
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                    handler_test.ex
                  </span>
                  <span class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">README.md</span>
                </div>
              </div>
            <% else %>
              <p class="text-xs text-muted-foreground">
                Select a template above, or
                <.button
                  type="button"
                  variant="ghost"
                  phx-click="switch_to_description"
                  class="h-auto w-auto p-0 underline hover:text-foreground hover:bg-transparent"
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
          <p class="text-xs text-muted-foreground">
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
