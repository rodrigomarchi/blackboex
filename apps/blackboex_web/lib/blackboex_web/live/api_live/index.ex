defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization with 24h stats.
  Includes inline modal for creating new APIs.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.Apis
  alias Blackboex.Apis.DashboardQueries

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
       create_error: nil
     )}
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
    org = socket.assigns.current_scope.organization

    case org && Apis.get_api(org.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "API not found.")}

      api ->
        case Apis.delete_api(api) do
          {:ok, _api} ->
            api_rows =
              DashboardQueries.list_apis_with_stats(org.id, search: socket.assigns.search)

            {:noreply, socket |> assign(api_rows: api_rows) |> put_flash(:info, "API deleted.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not delete API.")}
        end
    end
  end

  # ── Create Modal ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_form: to_form(%{"name" => "", "description" => ""}),
       create_error: nil
     )}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  @impl true
  def handle_event("create_api", %{"name" => name, "description" => description}, socket) do
    name = String.trim(name)
    description = String.trim(description)

    case validate_create_inputs(name, description) do
      {:error, msg} ->
        {:noreply, assign(socket, create_error: msg)}

      :ok ->
        do_create_api(socket, name, description)
    end
  end

  defp validate_create_inputs("", _description), do: {:error, "Name is required"}

  defp validate_create_inputs(_name, description) do
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
    has_description = description != ""

    attrs = %{
      name: name,
      description: if(has_description, do: description, else: nil),
      generation_status: if(has_description, do: "pending", else: nil),
      organization_id: org.id,
      user_id: user.id
    }

    case Apis.create_api(attrs) do
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

  defp maybe_enqueue_generation(_api, "", _user_id, _org_id), do: :ok

  defp maybe_enqueue_generation(api, description, user_id, _org_id) do
    Apis.start_agent_generation(api, description, user_id)
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        APIs
        <:subtitle>Manage and monitor your API endpoints</:subtitle>
        <:actions>
          <.button variant="primary" phx-click="open_create_modal">
            <.icon name="hero-plus" class="mr-2 size-4" /> Create API
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
        <div class="space-y-3">
          <.card :for={row <- @api_rows} class="p-4">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1 space-y-1">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/apis/#{row.api.id}/edit"}
                    class="font-semibold hover:underline truncate"
                  >
                    {row.api.name}
                  </.link>
                  <.badge class={api_status_classes(row.api.status)}>{row.api.status}</.badge>
                  <.generation_badge
                    :if={row.api.generation_status in ~w(pending generating validating)}
                    status={row.api.generation_status}
                  />
                </div>

                <p :if={row.api.description} class="text-sm text-muted-foreground truncate">
                  {row.api.description}
                </p>

                <div class="flex items-center gap-3 text-xs text-muted-foreground">
                  <span>{row.calls_24h} calls</span>
                  <span>&middot;</span>
                  <span>{format_latency(row.avg_latency)} avg</span>
                  <span>&middot;</span>
                  <span>{row.errors_24h} errors</span>
                  <span>&middot;</span>
                  <span>{Calendar.strftime(row.api.inserted_at, "%Y-%m-%d")}</span>
                </div>

                <%= if row.api.status == "published" do %>
                  <div class="flex items-center gap-2 pt-1">
                    <code class="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                      POST /api/{@org_slug}/{row.api.slug}
                    </code>
                  </div>
                <% else %>
                  <p class="text-xs italic text-muted-foreground pt-1">Not published</p>
                <% end %>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <.button variant="outline" size="sm" navigate={~p"/apis/#{row.api.id}/edit"}>
                  Edit
                </.button>
                <.button
                  variant="destructive"
                  size="sm"
                  phx-click="delete"
                  phx-value-id={row.api.id}
                  data-confirm="Are you sure you want to delete this API?"
                >
                  Delete
                </.button>
              </div>
            </div>
          </.card>
        </div>
      <% end %>

      <%!-- Create API Modal --%>
      <.modal show={@show_create_modal} on_close="close_create_modal" title="Create API">
        <%= if @create_error do %>
          <div class="mb-4 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
            {@create_error}
          </div>
        <% end %>

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
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click="close_create_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary">
              <.icon name="hero-arrow-right" class="mr-2 size-4" /> Create & Edit
            </.button>
          </div>
        </form>
      </.modal>
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
