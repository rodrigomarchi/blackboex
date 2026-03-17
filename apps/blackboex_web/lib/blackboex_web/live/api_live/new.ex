defmodule BlackboexWeb.ApiLive.New do
  @moduledoc """
  LiveView for creating a new API from a natural language description.
  Generates code via LLM (in async Task) and allows saving as a draft.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Apis
  alias Blackboex.CodeGen.Pipeline
  alias Blackboex.LLM
  alias Blackboex.LLM.RateLimiter

  @max_description_length 10_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create API",
       description: "",
       generated_code: nil,
       generation_result: nil,
       generating: false,
       error: nil,
       save_form: to_form(%{"name" => "", "slug" => ""}),
       task_ref: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Create API</h1>
          <p class="text-muted-foreground">Describe your API in natural language</p>
        </div>

        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <form id="generate-form" phx-submit="generate" class="space-y-4">
            <div>
              <label for="description" class="text-sm font-medium">Description</label>
              <textarea
                id="description"
                name="description"
                rows="4"
                maxlength="10000"
                placeholder="Describe what your API should do. E.g.: An API that converts Celsius to Fahrenheit"
                class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                disabled={@generating}
              >{@description}</textarea>
            </div>
            <button
              type="submit"
              disabled={@generating}
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 disabled:opacity-50"
            >
              <%= if @generating do %>
                <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" /> Generating...
              <% else %>
                <.icon name="hero-bolt" class="mr-2 size-4" /> Generate
              <% end %>
            </button>
          </form>
        </div>

        <%= if @error do %>
          <div class="rounded-lg border border-destructive bg-destructive/10 p-4 text-sm text-destructive">
            {@error}
          </div>
        <% end %>

        <%= if @generated_code do %>
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
            <h2 class="text-lg font-semibold">Generated Code</h2>
            <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@generated_code}</code></pre>

            <form id="save-form" phx-submit="save" class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label for="api-name" class="text-sm font-medium">Name</label>
                  <input
                    type="text"
                    id="api-name"
                    name="name"
                    value={@save_form[:name].value}
                    placeholder="My API"
                    required
                    maxlength="200"
                    class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label for="api-slug" class="text-sm font-medium">Slug</label>
                  <input
                    type="text"
                    id="api-slug"
                    name="slug"
                    value={@save_form[:slug].value}
                    placeholder="my-api (auto-generated if empty)"
                    maxlength="100"
                    class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
                  />
                </div>
              </div>
              <button
                type="submit"
                class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
              >
                <.icon name="hero-document-check" class="mr-2 size-4" /> Save as Draft
              </button>
            </form>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("generate", %{"description" => description}, socket) do
    description = String.trim(description)

    cond do
      description == "" ->
        {:noreply, assign(socket, error: "Please enter a description")}

      String.length(description) > @max_description_length ->
        {:noreply,
         assign(socket,
           error: "Description too long (max #{@max_description_length} characters)"
         )}

      true ->
        start_generation(socket, description)
    end
  end

  @impl true
  def handle_event("save", %{"name" => name, "slug" => slug}, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    user = scope.user

    slug = if String.trim(slug) == "", do: nil, else: slug

    case Apis.create_api(%{
           name: name,
           slug: slug,
           description: socket.assigns.description,
           source_code: socket.assigns.generated_code,
           template_type: to_string(Pipeline.classify_type(socket.assigns.description)),
           organization_id: org.id,
           user_id: user.id
         }) do
      {:ok, _api} ->
        maybe_record_usage(socket)

        {:noreply,
         socket
         |> put_flash(:info, "API saved as draft")
         |> push_navigate(to: ~p"/apis")}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:noreply, assign(socket, error: errors)}
    end
  end

  @impl true
  def handle_info({ref, {:ok, result}}, %{assigns: %{task_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     assign(socket,
       generating: false,
       generated_code: result.code,
       generation_result: result,
       save_form: to_form(%{"name" => "", "slug" => ""}),
       task_ref: nil
     )}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, %{assigns: %{task_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     assign(socket,
       generating: false,
       error: "Generation failed: #{reason}",
       task_ref: nil
     )}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{task_ref: ref}} = socket) do
    {:noreply,
     assign(socket,
       generating: false,
       error: "Generation process crashed unexpectedly. Please try again.",
       task_ref: nil
     )}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp start_generation(socket, description) do
    scope = socket.assigns.current_scope
    plan = (scope.organization && scope.organization.plan) || :free

    case RateLimiter.check_rate(to_string(scope.user.id), plan) do
      :ok ->
        task = Task.async(fn -> Pipeline.generate(description, user_id: scope.user.id) end)

        {:noreply,
         assign(socket,
           generating: true,
           error: nil,
           description: description,
           generated_code: nil,
           generation_result: nil,
           task_ref: task.ref
         )}

      {:error, :rate_limited} ->
        {:noreply,
         assign(socket,
           error: "Rate limit exceeded. Please wait before generating again."
         )}
    end
  end

  defp maybe_record_usage(socket) do
    case socket.assigns.generation_result do
      nil ->
        :ok

      result ->
        scope = socket.assigns.current_scope

        LLM.record_usage(%{
          user_id: scope.user.id,
          organization_id: scope.organization.id,
          provider: result.provider,
          model: result.model || "unknown",
          input_tokens: result.tokens_used,
          output_tokens: 0,
          cost_cents: 0,
          operation: "code_generation",
          duration_ms: result.duration_ms
        })
    end
  end

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
