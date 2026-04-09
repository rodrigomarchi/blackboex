defmodule BlackboexWeb.FlowLive.Index do
  @moduledoc """
  LiveView listing Flows for the current organization.
  Includes inline modal for creating new flows.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
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
       create_mode: :blank,
       selected_template: nil,
       templates: Templates.list(),
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
       create_mode: :blank,
       selected_template: nil,
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
        Flows
        <:subtitle>Build visual workflows by connecting nodes</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="open_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4" /> Create Flow
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
        <div class="space-y-3">
          <.card :for={flow <- @flows} class="p-4">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1 space-y-1">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/flows/#{flow.id}/edit"}
                    class="font-semibold hover:underline truncate"
                  >
                    {flow.name}
                  </.link>
                  <.badge class={flow_status_classes(flow.status)}>{flow.status}</.badge>
                </div>

                <p :if={flow.description} class="text-sm text-muted-foreground truncate">
                  {flow.description}
                </p>

                <div class="flex items-center gap-3 text-xs text-muted-foreground">
                  <span>{Calendar.strftime(flow.inserted_at, "%Y-%m-%d")}</span>
                </div>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <.button variant="outline" size="sm" navigate={~p"/flows/#{flow.id}/edit"}>
                  Edit
                </.button>
                <.button
                  variant="destructive"
                  size="sm"
                  phx-click="request_confirm"
                  phx-value-action="delete"
                  phx-value-id={flow.id}
                >
                  Delete
                </.button>
              </div>
            </div>
          </.card>
        </div>
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

        <%!-- Mode Tabs --%>
        <div class="mb-4 flex border-b border-border">
          <button
            type="button"
            phx-click="set_create_mode"
            phx-value-mode="template"
            class={"px-4 py-2 text-sm font-medium border-b-2 -mb-px #{if @create_mode == :template, do: "border-primary text-primary", else: "border-transparent text-muted-foreground hover:text-foreground"}"}
          >
            From Template
          </button>
          <button
            type="button"
            phx-click="set_create_mode"
            phx-value-mode="blank"
            class={"px-4 py-2 text-sm font-medium border-b-2 -mb-px #{if @create_mode == :blank, do: "border-primary text-primary", else: "border-transparent text-muted-foreground hover:text-foreground"}"}
          >
            Blank Flow
          </button>
        </div>

        <%!-- Template Picker --%>
        <div :if={@create_mode == :template} class="mb-4">
          <div class="grid grid-cols-1 gap-3">
            <button
              :for={t <- @templates}
              type="button"
              phx-click="select_template"
              phx-value-id={t.id}
              class={"flex items-start gap-3 rounded-lg border p-3 text-left transition-colors #{if @selected_template && @selected_template.id == t.id, do: "border-primary bg-primary/5 ring-1 ring-primary", else: "border-border hover:border-muted-foreground/50"}"}
            >
              <div class="flex size-10 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
                <.icon name={t.icon} class="size-5" />
              </div>
              <div class="min-w-0">
                <div class="font-medium text-sm">{t.name}</div>
                <div class="text-xs text-muted-foreground mt-0.5">{t.description}</div>
                <div class="text-xs text-muted-foreground/70 mt-1">
                  {length(t.definition["nodes"])} nodes
                </div>
              </div>
            </button>
          </div>
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

  defp build_confirm("delete", params) do
    %{
      title: "Delete flow?",
      description: "This action cannot be undone. The flow and all its data will be permanently removed.",
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
