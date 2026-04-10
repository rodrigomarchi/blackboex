defmodule BlackboexWeb.FlowLive.Index do
  @moduledoc """
  LiveView listing Flows for the current organization.
  Includes inline modal for creating new flows.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.Flows
  alias Blackboex.Flows.Templates
  alias Blackboex.Policy

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    flows =
      if org do
        Flows.list_flows(org.id)
      else
        []
      end

    {:ok,
     assign(socket,
       flows: flows,
       search: "",
       page_title: "Flows",
       show_create_modal: false,
       create_mode: :template,
       selected_template: nil,
       template_categories: Templates.list_by_category(),
       active_category: get_first_category(),
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil,
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
      nil ->
        {:noreply, socket}

      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
    end
  end

  # ── Search ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    query = String.slice(query, 0, 200)
    org = socket.assigns.current_scope.organization

    flows =
      if org do
        Flows.list_flows(org.id, search: query)
      else
        []
      end

    {:noreply, assign(socket, flows: flows, search: query)}
  end

  # ── Delete ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    with :ok <- Policy.authorize_and_track(:flow_delete, scope, org),
         flow when not is_nil(flow) <- org && Flows.get_flow(org.id, id) do
      case Flows.delete_flow(flow) do
        {:ok, _flow} ->
          flows = Flows.list_flows(org.id, search: socket.assigns.search)
          {:noreply, socket |> assign(flows: flows) |> put_flash(:info, "Flow deleted.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not delete flow.")}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
      nil -> {:noreply, put_flash(socket, :error, "Flow not found.")}
      false -> {:noreply, put_flash(socket, :error, "Flow not found.")}
    end
  end

  # ── Create Modal ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_mode: :template,
       selected_template: nil,
       active_category: get_first_category(),
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil
     )}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  @impl true
  def handle_event("set_create_mode", %{"mode" => "blank"}, socket) do
    {:noreply, assign(socket, create_mode: :blank, selected_template: nil, create_error: nil)}
  end

  def handle_event("set_create_mode", %{"mode" => "template"}, socket) do
    {:noreply, assign(socket, create_mode: :template, create_error: nil)}
  end

  @impl true
  def handle_event("set_active_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, active_category: cat, selected_template: nil)}
  end

  @impl true
  def handle_event("select_template", %{"id" => template_id}, socket) do
    template = Templates.get(template_id)

    {:noreply,
     assign(socket,
       selected_template: template,
       create_form: to_form(%{"name" => template.name, "description" => template.description})
     )}
  end

  @impl true
  def handle_event("create_flow", %{"name" => name, "description" => description}, socket) do
    name = String.trim(name)
    description = String.trim(description)

    if name == "" do
      {:noreply, assign(socket, create_error: "Name is required")}
    else
      do_create_flow(socket, name, description)
    end
  end

  defp do_create_flow(socket, name, description) do
    scope = socket.assigns.current_scope
    org = scope.organization
    user = scope.user

    with :ok <- Policy.authorize_and_track(:flow_create, scope, org) do
      attrs = %{
        name: name,
        description: if(description != "", do: description, else: nil),
        organization_id: org.id,
        user_id: user.id
      }

      result =
        case socket.assigns.selected_template do
          nil -> Flows.create_flow(attrs)
          template -> Flows.create_flow_from_template(attrs, template.id)
        end

      case result do
        {:ok, flow} ->
          {:noreply, push_navigate(socket, to: ~p"/flows/#{flow.id}/edit")}

        {:error, :limit_exceeded, details} ->
          {:noreply,
           assign(socket,
             create_error:
               "You've reached the #{details.plan} plan limit of #{details.limit} flows."
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, create_error: format_changeset_errors(changeset))}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-arrow-path" class="size-5 text-violet-400" /> Flows
        </span>
        <:subtitle>Build visual workflows by connecting nodes</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="open_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4 text-emerald-300" /> Create Flow
          </.button>
        </:actions>
      </.header>

      <form phx-change="search" class="w-full">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search flows by name or description..."
          phx-debounce="300"
        />
      </form>

      <%= if @flows == [] do %>
        <.empty_state
          icon="hero-arrow-path"
          title="No flows found"
          description={
            if @search != "",
              do: "No flows match your search. Try a different query.",
              else: "Get started by creating your first visual workflow."
          }
        >
          <:actions :if={@search == ""}>
            <.button variant="primary" phx-click="open_create_modal">Create Flow</.button>
          </:actions>
        </.empty_state>
      <% else %>
        <.table id="flows" rows={@flows}>
          <:col :let={flow} label="Flow">
            <div class="flex items-center gap-3">
              <div class="flex size-8 items-center justify-center rounded-lg bg-violet-500/15">
                <.icon name="hero-arrow-path" class="size-4 text-violet-400" />
              </div>
              <div class="min-w-0">
                <.link
                  navigate={~p"/flows/#{flow.id}/edit"}
                  class="font-medium text-sm hover:underline truncate block"
                >
                  {flow.name}
                </.link>
                <p :if={flow.description} class="text-xs text-muted-foreground truncate max-w-xs">
                  {flow.description}
                </p>
              </div>
            </div>
          </:col>
          <:col :let={flow} label="Status">
            <.badge class={flow_status_classes(flow.status)}>{flow.status}</.badge>
          </:col>
          <:col :let={flow} label="Created">
            <span class="text-xs text-muted-foreground">
              {Calendar.strftime(flow.inserted_at, "%b %d, %Y")}
            </span>
          </:col>
          <:action :let={flow}>
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/flows/#{flow.id}/edit"}
                class="inline-flex items-center text-xs text-primary hover:underline"
              >
                <.icon name="hero-pencil-square-mini" class="mr-1 size-3" /> Edit
              </.link>
              <button
                phx-click="request_confirm"
                phx-value-action="delete"
                phx-value-id={flow.id}
                class="inline-flex items-center text-xs text-destructive hover:underline"
              >
                <.icon name="hero-trash-mini" class="mr-1 size-3" /> Delete
              </button>
            </div>
          </:action>
        </.table>
      <% end %>

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />

      <%!-- Create Flow Modal --%>
      <.modal show={@show_create_modal} on_close="close_create_modal" title="Create Flow">
        <%= if @create_error do %>
          <div class="mb-4 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
            {@create_error}
          </div>
        <% end %>

        <%!-- Mode Toggle --%>
        <div class="flex gap-1 rounded-lg bg-muted p-1 mb-4">
          <button
            type="button"
            phx-click="set_create_mode"
            phx-value-mode="template"
            class={[
              "flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              if(@create_mode == :template,
                do: "bg-background text-foreground shadow-sm",
                else: "text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            <.icon name="hero-squares-2x2" class="mr-1.5 size-4 inline" /> From template
          </button>
          <button
            type="button"
            phx-click="set_create_mode"
            phx-value-mode="blank"
            class={[
              "flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              if(@create_mode == :blank,
                do: "bg-background text-foreground shadow-sm",
                else: "text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            <.icon name="hero-document-plus" class="mr-1.5 size-4 inline" /> Blank flow
          </button>
        </div>

        <%!-- Template Picker --%>
        <div :if={@create_mode == :template} class="mb-4 space-y-3">
          <%!-- Category Pills --%>
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

          <%!-- Template Grid --%>
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
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Helper text --%>
          <p :if={is_nil(@selected_template)} class="text-xs text-muted-foreground">
            Select a template above, or switch to
            <button
              type="button"
              phx-click="set_create_mode"
              phx-value-mode="blank"
              class="underline hover:text-foreground"
            >
              blank flow
            </button>
            to start from scratch.
          </p>
        </div>

        <form phx-submit="create_flow" class="space-y-4">
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
        </form>
      </.modal>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp get_first_category do
    case Templates.list_by_category() do
      [{cat, _} | _] -> cat
      [] -> nil
    end
  end

  defp build_confirm("delete", params) do
    %{
      title: "Delete flow?",
      description:
        "This action cannot be undone. The flow and all its data will be permanently removed.",
      variant: :danger,
      confirm_label: "Delete",
      event: "delete",
      meta: Map.take(params, ["id"])
    }
  end

  defp build_confirm(_, _), do: nil

  defp flow_status_classes("draft"), do: "bg-muted text-muted-foreground"

  defp flow_status_classes("active"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp flow_status_classes("archived"),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp flow_status_classes(_), do: "bg-muted text-muted-foreground"

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
