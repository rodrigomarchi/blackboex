defmodule BlackboexWeb.FlowLive.Index do
  @moduledoc """
  LiveView listing Flows for the current organization.
  Includes inline modal for creating new flows.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.IconBadge
  import BlackboexWeb.FlowLive.Components.CreateFlowModal

  alias Blackboex.Flows
  alias Blackboex.Flows.Templates
  alias Blackboex.Policy
  alias BlackboexWeb.FlowLive.IndexHelpers

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
       active_category: IndexHelpers.get_first_category(),
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil,
       confirm: nil
     )}
  end

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = IndexHelpers.build_confirm(params["action"], params)
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
       active_category: IndexHelpers.get_first_category(),
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
      project = Blackboex.Projects.get_default_project(org.id)

      attrs = %{
        name: name,
        description: if(description != "", do: description, else: nil),
        organization_id: org.id,
        project_id: project && project.id,
        user_id: user.id
      }

      result =
        case socket.assigns.selected_template do
          nil -> Flows.create_flow(attrs)
          template -> Flows.create_flow_from_template(attrs, template.id)
        end

      case result do
        {:ok, flow} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/flows/#{flow.id}/edit"
           )}

        {:error, :limit_exceeded, details} ->
          {:noreply,
           assign(socket,
             create_error:
               "You've reached the #{details.plan} plan limit of #{details.limit} flows."
           )}

        {:error, changeset} ->
          {:noreply,
           assign(socket, create_error: IndexHelpers.format_changeset_errors(changeset))}
      end
    else
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header icon="hero-arrow-path" icon_class="text-accent-violet" title="Flows">
      <:actions>
        <.button variant="primary" phx-click="open_create_modal">
          <.icon name="hero-plus" class="mr-2 size-4 text-accent-emerald" /> Create Flow
        </.button>
      </:actions>
    </.page_header>
    <.page>

      <.form :let={_f} for={%{}} as={:search} phx-change="search" class="w-full">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search flows by name or description..."
          phx-debounce="300"
        />
      </.form>

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
              <.icon_badge icon="hero-arrow-path" color="accent-violet" />
              <div class="min-w-0">
                <.link
                  navigate={~p"/flows/#{flow.id}/edit"}
                  class="font-medium text-sm hover:underline truncate block"
                >
                  {flow.name}
                </.link>
                <p :if={flow.description} class="text-muted-caption truncate max-w-xs">
                  {flow.description}
                </p>
              </div>
            </div>
          </:col>
          <:col :let={flow} label="Status">
            <.badge class={IndexHelpers.flow_status_classes(flow.status)}>{flow.status}</.badge>
          </:col>
          <:col :let={flow} label="Created">
            <span class="text-muted-caption">
              {Calendar.strftime(flow.inserted_at, "%b %d, %Y")}
            </span>
          </:col>
          <:action :let={flow}>
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/flows/#{flow.id}/edit"}
                class="inline-flex items-center link-primary"
              >
                <.icon name="hero-pencil-square-mini" class="mr-1 size-3" /> Edit
              </.link>
              <.button
                phx-click="request_confirm"
                phx-value-action="delete"
                phx-value-id={flow.id}
                variant="link"
                size="sm"
                class="link-destructive"
              >
                <.icon name="hero-trash-mini" class="mr-1 size-3" /> Delete
              </.button>
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

      <.create_flow_modal
        show={@show_create_modal}
        create_mode={@create_mode}
        selected_template={@selected_template}
        template_categories={@template_categories}
        active_category={@active_category}
        create_form={@create_form}
        create_error={@create_error}
      />
    </.page>
    """
  end
end
