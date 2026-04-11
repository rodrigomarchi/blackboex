defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization with 24h stats.
  Includes inline modal for creating new APIs, with template library support.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.IndexComponents

  alias Blackboex.Apis
  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Apis.Templates
  alias Blackboex.Policy
  alias BlackboexWeb.ApiLive.IndexHelpers

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
        {:noreply, assign(socket, create_error: IndexHelpers.format_changeset_errors(changeset))}
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
        {:noreply, assign(socket, create_error: IndexHelpers.format_changeset_errors(changeset))}
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
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-cube" class="size-5 text-accent-blue" /> APIs
        </span>
        <:subtitle>Manage and monitor your API endpoints</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="open_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4 text-accent-emerald" /> Create API
          </.button>
        </:actions>
      </.header>

      <.form :let={_f} for={%{}} as={:search} phx-change="search" class="w-full">
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder="Search APIs by name or description..."
          phx-debounce="300"
        />
      </.form>

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
        <.api_table api_rows={@api_rows} org_slug={@org_slug} />
      <% end %>

      <.create_modal
        show_create_modal={@show_create_modal}
        create_error={@create_error}
        creation_mode={@creation_mode}
        create_form={@create_form}
        template_categories={@template_categories}
        active_category={@active_category}
        selected_template={@selected_template}
      />

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />
    </.page>
    """
  end
end
