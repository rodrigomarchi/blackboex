defmodule BlackboexWeb.ApiLive.Index do
  @moduledoc """
  LiveView listing APIs for the current organization with 24h stats.
  Includes inline modal for creating new APIs.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Apis
  alias Blackboex.Apis.Conversations
  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.CodeGen.GenerationWorker

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

  defp maybe_enqueue_generation(api, description, user_id, org_id) do
    # Seed the conversation with the user's prompt so the editor chat shows it immediately
    {:ok, conversation} = Conversations.get_or_create_conversation(api.id)
    Conversations.append_message(conversation, "user", description)

    %{api_id: api.id, description: description, user_id: user_id, org_id: org_id}
    |> GenerationWorker.new()
    |> Oban.insert()
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">APIs</h1>
          <p class="text-muted-foreground">Manage and monitor your API endpoints</p>
        </div>
        <button
          phx-click="open_create_modal"
          class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Create API
        </button>
      </div>

      <form phx-change="search" class="w-full">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder="Search APIs by name or description..."
          phx-debounce="300"
          class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
      </form>

      <%= if @api_rows == [] do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <div class="flex flex-col items-center justify-center space-y-4 py-8">
            <div class="text-center space-y-2">
              <h3 class="text-lg font-semibold">No APIs found</h3>
              <p class="text-sm text-muted-foreground">
                <%= if @search != "" do %>
                  No APIs match your search. Try a different query.
                <% else %>
                  Get started by creating your first API endpoint.
                <% end %>
              </p>
            </div>
            <button
              :if={@search == ""}
              phx-click="open_create_modal"
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
            >
              Create API
            </button>
          </div>
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={row <- @api_rows}
            class="rounded-lg border bg-card p-4 text-card-foreground shadow-sm"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1 space-y-1">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/apis/#{row.api.id}"}
                    class="font-semibold hover:underline truncate"
                  >
                    {row.api.name}
                  </.link>
                  <.status_badge status={row.api.status} />
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
                <.link
                  navigate={~p"/apis/#{row.api.id}/edit"}
                  class="inline-flex items-center rounded-md border px-2.5 py-1 text-xs font-medium hover:bg-accent"
                >
                  Edit
                </.link>
                <.link
                  phx-click="delete"
                  phx-value-id={row.api.id}
                  data-confirm="Are you sure you want to delete this API?"
                  class="inline-flex items-center rounded-md border border-destructive/50 px-2.5 py-1 text-xs font-medium text-destructive hover:bg-destructive/10"
                >
                  Delete
                </.link>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Create API Modal --%>
      <div
        :if={@show_create_modal}
        class="fixed inset-0 z-50 flex items-center justify-center"
        phx-window-keydown="close_create_modal"
        phx-key="Escape"
      >
        <div class="fixed inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_create_modal" />
        <div class="relative z-10 w-full max-w-lg rounded-lg border bg-card p-6 shadow-xl">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold">Create API</h2>
            <button
              phx-click="close_create_modal"
              class="rounded-md p-1 text-muted-foreground hover:text-foreground hover:bg-accent"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%= if @create_error do %>
            <div class="mb-4 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
              {@create_error}
            </div>
          <% end %>

          <form phx-submit="create_api" class="space-y-4">
            <div>
              <label for="create-name" class="text-sm font-medium">Name *</label>
              <input
                type="text"
                id="create-name"
                name="name"
                value={@create_form[:name].value}
                required
                maxlength="200"
                placeholder="My API"
                class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                autofocus
              />
            </div>
            <div>
              <label for="create-description" class="text-sm font-medium">
                What should this API do?
              </label>
              <textarea
                id="create-description"
                name="description"
                rows="4"
                maxlength="10000"
                placeholder="An API that receives a list of products with prices and returns the total, average, and most expensive item."
                class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
              >{@create_form[:description].value}</textarea>
              <p class="mt-1 text-xs text-muted-foreground">
                Describe in natural language. Code will be generated automatically.
              </p>
            </div>
            <div class="flex justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_create_modal"
                class="rounded-md border px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-accent"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
              >
                <.icon name="hero-arrow-right" class="mr-2 size-4" /> Create & Edit
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ── Components ───────────────────────────────────────────────────────────

  defp status_badge(assigns) do
    color_classes =
      case assigns.status do
        "published" ->
          "border-green-500/30 bg-green-500/10 text-green-700 dark:text-green-400"

        "compiled" ->
          "border-border bg-secondary text-secondary-foreground"

        _draft_or_other ->
          "border-border bg-muted text-muted-foreground"
      end

    assigns = assign(assigns, :color_classes, color_classes)

    ~H"""
    <span class={"inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-semibold #{@color_classes}"}>
      {@status}
    </span>
    """
  end

  attr :status, :string, required: true

  defp generation_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-0.5 text-xs font-semibold text-amber-700 dark:text-amber-400 animate-pulse">
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
