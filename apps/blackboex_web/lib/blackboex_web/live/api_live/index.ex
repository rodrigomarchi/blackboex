defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization with 24h stats.
  Includes inline modal for creating new APIs, with template library support.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.Apis
  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Apis.Templates
  alias Blackboex.Policy

  @max_description_length 10_000

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    {api_rows, org_slug} =
      if org do
        {DashboardQueries.list_apis_with_stats(org.id), org.slug}
      else
        {[], nil}
      end

    {:ok,
     assign(socket,
       api_rows: api_rows,
       org_slug: org_slug,
       search: "",
       page_title: "APIs",
       show_create_modal: false,
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil,
       selected_template: nil,
       template_categories: [],
       active_category: nil,
       creation_mode: :template,
       confirm: nil
     )}
  end

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = build_confirm(params["action"], params)
    {:noreply, assign(socket, confirm: confirm)}
  end

  @impl true
  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end

  @impl true
  def handle_event("execute_confirm", _params, socket) do
    case socket.assigns.confirm do
      nil -> {:noreply, socket}
      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
    end
  end

  # ── Search ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    query = String.slice(query, 0, 200)
    org = socket.assigns.current_scope.organization

    api_rows =
      if org do
        DashboardQueries.list_apis_with_stats(org.id, search: query)
      else
        []
      end

    {:noreply, assign(socket, api_rows: api_rows, search: query)}
  end

  # ── Delete ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:api_delete, scope, org),
         api when not is_nil(api) <- org && Apis.get_api(org.id, id) do
      case Apis.delete_api(api) do
        {:ok, _api} ->
          api_rows =
            DashboardQueries.list_apis_with_stats(org.id, search: socket.assigns.search)

          {:noreply, socket |> assign(api_rows: api_rows) |> put_flash(:info, "API deleted.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not delete API.")}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
      nil -> {:noreply, put_flash(socket, :error, "API not found.")}
      false -> {:noreply, put_flash(socket, :error, "API not found.")}
    end
  end

  # ── Create Modal ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    categories = Templates.list_by_category()

    first_category =
      case categories do
        [{cat, _} | _] -> cat
        [] -> nil
      end

    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil,
       selected_template: nil,
       template_categories: categories,
       active_category: first_category,
       creation_mode: :template
     )}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  @impl true
  def handle_event("switch_to_template", _params, socket) do
    {:noreply, assign(socket, creation_mode: :template, selected_template: nil)}
  end

  @impl true
  def handle_event("switch_to_description", _params, socket) do
    {:noreply, assign(socket, creation_mode: :description, selected_template: nil)}
  end

  @impl true
  def handle_event("set_active_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, active_category: cat, selected_template: nil)}
  end

  @impl true
  def handle_event("select_template", %{"id" => id}, socket) do
    template = Templates.get(id)

    socket =
      if template do
        name_value = socket.assigns.create_form[:name].value
        updated_name = if name_value == "", do: template.name, else: name_value

        assign(socket,
          selected_template: template,
          create_form: to_form(%{"name" => updated_name, "description" => ""})
        )
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_template", _params, socket) do
    {:noreply, assign(socket, selected_template: nil)}
  end

  @impl true
  def handle_event("create_api", %{"name" => name, "description" => description}, socket) do
    name = String.trim(name)
    description = String.trim(description)

    case validate_create_inputs(name, description, socket.assigns.selected_template) do
      {:error, msg} ->
        {:noreply, assign(socket, create_error: msg)}

      :ok ->
        do_create_api(socket, name, description)
    end
  end

  defp validate_create_inputs("", _description, _template), do: {:error, "Name is required"}

  defp validate_create_inputs(_name, _description, template) when not is_nil(template), do: :ok

  defp validate_create_inputs(_name, description, _template) do
    if String.length(description) > @max_description_length do
      {:error, "Description too long (max #{@max_description_length} characters)"}
    else
      :ok
    end
  end

  defp do_create_api(socket, name, description) do
    scope = socket.assigns.current_scope
    org = scope.organization
    user = scope.user

    with :ok <- Policy.authorize_and_track(:api_create, scope, org) do
      case socket.assigns.selected_template do
        nil ->
          do_create_from_description(socket, name, description, org, user)

        template ->
          do_create_from_template(socket, name, template, org, user)
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  defp do_create_from_description(socket, name, description, org, user) do
    has_description = description != ""

    attrs = %{
      name: name,
      description: if(has_description, do: description, else: nil),
      generation_status: if(has_description, do: "pending", else: nil),
      organization_id: org.id,
      user_id: user.id
    }

    case Apis.create_api_with_files(attrs) do
      {:ok, api} ->
        maybe_enqueue_generation(api, description, user.id, org.id)
        {:noreply, push_navigate(socket, to: ~p"/apis/#{api.id}/edit")}

      {:error, :limit_exceeded, details} ->
        {:noreply,
         assign(socket,
           create_error: "You've reached the #{details.plan} plan limit of #{details.limit} APIs."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, create_error: format_changeset_errors(changeset))}
    end
  end

  defp do_create_from_template(socket, name, template, org, user) do
    attrs = %{
      name: name,
      organization_id: org.id,
      user_id: user.id
    }

    case Apis.create_api_from_template(attrs, template.id) do
      {:ok, api} ->
        {:noreply, push_navigate(socket, to: ~p"/apis/#{api.id}/edit")}

      {:error, :template_not_found} ->
        {:noreply, assign(socket, create_error: "Template not found.")}

      {:error, :limit_exceeded, details} ->
        {:noreply,
         assign(socket,
           create_error: "You've reached the #{details.plan} plan limit of #{details.limit} APIs."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, create_error: format_changeset_errors(changeset))}
    end
  end

  defp maybe_enqueue_generation(_api, "", _user_id, _org_id), do: :ok

  defp maybe_enqueue_generation(api, description, user_id, _org_id) do
    Blackboex.Agent.start_generation(api, description, user_id)
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-cube" class="size-5 text-blue-400" /> APIs
        </span>
        <:subtitle>Manage and monitor your API endpoints</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="open_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4 text-emerald-300" /> Create API
          </.button>
        </:actions>
      </.header>

      <form phx-change="search" class="w-full">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search APIs by name or description..."
          phx-debounce="300"
        />
      </form>

      <%= if @api_rows == [] do %>
        <.empty_state
          icon="hero-square-3-stack-3d"
          title="No APIs found"
          description={
            if @search != "",
              do: "No APIs match your search. Try a different query.",
              else: "Get started by creating your first API endpoint."
          }
        >
          <:actions :if={@search == ""}>
            <.button variant="primary" phx-click="open_create_modal">Create API</.button>
          </:actions>
        </.empty_state>
      <% else %>
        <.table id="apis" rows={@api_rows}>
          <:col :let={row} label="API">
            <div class="flex items-center gap-3">
              <div class="flex size-8 items-center justify-center rounded-lg bg-blue-500/15">
                <.icon name="hero-cube" class="size-4 text-blue-400" />
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
              <.icon name="hero-signal-mini" class="size-3.5 text-sky-400" />
              <span class="text-xs font-mono">{row.calls_24h}</span>
            </div>
          </:col>
          <:col :let={row} label="Avg Latency">
            <div class="flex items-center gap-1.5">
              <.icon name="hero-clock-mini" class="size-3.5 text-amber-400" />
              <span class="text-xs font-mono">{format_latency(row.avg_latency)}</span>
            </div>
          </:col>
          <:col :let={row} label="Errors">
            <div class="flex items-center gap-1.5">
              <.icon name="hero-exclamation-circle-mini" class={"size-3.5 #{if row.errors_24h > 0, do: "text-red-400", else: "text-muted-foreground/50"}"} />
              <span class={"text-xs font-mono #{if row.errors_24h > 0, do: "text-red-400", else: ""}"}>{row.errors_24h}</span>
            </div>
          </:col>
          <:col :let={row} label="Endpoint">
            <%= if row.api.status == "published" do %>
              <code class="rounded bg-muted px-1.5 py-0.5 text-[11px] font-mono text-emerald-500">
                POST /{@org_slug}/{row.api.slug}
              </code>
            <% else %>
              <span class="text-xs italic text-muted-foreground">—</span>
            <% end %>
          </:col>
          <:action :let={row}>
            <div class="flex items-center gap-2">
              <.link navigate={~p"/apis/#{row.api.id}/edit"} class="inline-flex items-center text-xs text-primary hover:underline">
                <.icon name="hero-pencil-square-mini" class="mr-1 size-3" /> Edit
              </.link>
              <button
                phx-click="request_confirm"
                phx-value-action="delete"
                phx-value-id={row.api.id}
                class="inline-flex items-center text-xs text-destructive hover:underline"
              >
                <.icon name="hero-trash-mini" class="mr-1 size-3" /> Delete
              </button>
            </div>
          </:action>
        </.table>
      <% end %>

      <%!-- Create API Modal --%>
      <.modal show={@show_create_modal} on_close="close_create_modal" title="Create API">
        <%= if @create_error do %>
          <div class="mb-4 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
            {@create_error}
          </div>
        <% end %>

        <%!-- Mode toggle --%>
        <div class="flex gap-1 rounded-lg bg-muted p-1 mb-4">
          <button
            type="button"
            phx-click="switch_to_template"
            class={[
              "flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              if(@creation_mode == :template,
                do: "bg-background text-foreground shadow-sm",
                else: "text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            <.icon name="hero-squares-2x2" class="mr-1.5 size-4 inline" /> From template
          </button>
          <button
            type="button"
            phx-click="switch_to_description"
            class={[
              "flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              if(@creation_mode == :description,
                do: "bg-background text-foreground shadow-sm",
                else: "text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            <.icon name="hero-sparkles" class="mr-1.5 size-4 inline" /> Describe from scratch
          </button>
        </div>

        <form phx-submit="create_api" class="space-y-4">
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
                  <button
                    type="button"
                    phx-click="set_active_category"
                    phx-value-category={cat}
                    class={[
                      "rounded-full px-3 py-1 text-xs font-medium transition-colors border",
                      if(@active_category == cat,
                        do: "bg-primary text-primary-foreground border-primary",
                        else:
                          "bg-background text-muted-foreground border-border hover:border-primary/50 hover:text-foreground"
                      )
                    ]}
                  >
                    {cat}
                  </button>
                <% end %>
              </div>

              <%!-- Template grid --%>
              <div class="max-h-52 overflow-y-auto -mx-1 px-1">
                <div class="grid grid-cols-2 gap-2">
                  <%= for {cat, templates} <- @template_categories, cat == @active_category, template <- templates do %>
                    <button
                      type="button"
                      phx-click="select_template"
                      phx-value-id={template.id}
                      class={[
                        "flex items-start gap-2 rounded-lg border p-2.5 text-left transition-colors hover:border-primary/50",
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
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Selected template preview --%>
              <%= if @selected_template do %>
                <div class="rounded-lg border border-primary/30 bg-primary/5 p-3 space-y-1">
                  <div class="flex items-center justify-between">
                    <p class="text-sm font-medium">{@selected_template.name}</p>
                    <button
                      type="button"
                      phx-click="clear_template"
                      class="text-muted-foreground hover:text-foreground"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
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
                  <button
                    type="button"
                    phx-click="switch_to_description"
                    class="underline hover:text-foreground"
                  >
                    describe from scratch
                  </button>
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
          <%= if @creation_mode == :template do %>
            <input type="hidden" name="description" value="" />
          <% end %>

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
        </form>
      </.modal>

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />
    </div>
    """
  end

  # ── Components ───────────────────────────────────────────────────────────

  attr :status, :string, required: true

  defp generation_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full border border-warning/30 bg-warning/10 px-2 py-0.5 text-xs font-semibold text-warning-foreground animate-pulse">
      <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Generating...
    </span>
    """
  end

  defp build_confirm("delete", params) do
    %{
      title: "Delete API?",
      description: "This action cannot be undone. The API and all its versions will be permanently removed.",
      variant: :danger,
      confirm_label: "Delete",
      event: "delete",
      meta: Map.take(params, ["id"])
    }
  end

  defp build_confirm(_, _), do: nil

  defp format_latency(nil), do: "--"
  defp format_latency(ms) when ms < 1, do: "<1ms"
  defp format_latency(ms), do: "#{round(ms)}ms"

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
