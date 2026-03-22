defmodule BlackboexWeb.ApiLive.New do
  @moduledoc """
  LiveView for creating a new API from a natural language description.
  Generates code via LLM (streaming to UI) and allows saving as a draft.
  """

  use BlackboexWeb, :live_view

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.{GenerationResult, Pipeline, UnifiedPipeline}
  alias Blackboex.LLM
  alias Blackboex.LLM.{Config, Prompts, RateLimiter, StreamHandler}
  alias Blackboex.Telemetry.Events

  import BlackboexWeb.Components.PipelineStatus
  import BlackboexWeb.Components.ValidationDashboard

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
       streaming_tokens: "",
       error: nil,
       show_billing_link: false,
       save_form: to_form(%{"name" => "", "slug" => ""}),
       generation_meta: nil,
       pipeline_ref: nil,
       pipeline_status: nil,
       validating: false,
       validation_report: nil,
       test_code: nil,
       pipeline_tokens: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
          <p>{@error}</p>
          <%= if @show_billing_link do %>
            <.link navigate={~p"/billing"} class="mt-2 inline-block font-medium underline">
              Upgrade your plan
            </.link>
          <% end %>
        </div>
      <% end %>

      <%= if @generating && @streaming_tokens != "" do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Generating code...
          </h2>
          <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@streaming_tokens}</code></pre>
        </div>
      <% end %>

      <%!-- Validation progress --%>
      <%= if @validating do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Validating...
          </h2>
          <.pipeline_progress_steps status={@pipeline_status || :formatting} show_cancel={false} />
          <%= if @pipeline_tokens != "" do %>
            <pre class="overflow-x-auto rounded-md bg-muted p-4 text-xs max-h-40 overflow-y-auto"><code>{@pipeline_tokens}</code></pre>
          <% end %>
        </div>
      <% end %>

      <%= if @generated_code do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
          <h2 class="text-lg font-semibold">Generated Code</h2>
          <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@generated_code}</code></pre>

          <%!-- Test code --%>
          <%= if @test_code do %>
            <h2 class="text-lg font-semibold">Generated Tests</h2>
            <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm max-h-60 overflow-y-auto"><code>{@test_code}</code></pre>
          <% end %>

          <%!-- Validation results --%>
          <%= if @validation_report do %>
            <.validation_dashboard report={@validation_report} />
          <% end %>

          <form id="save-form" phx-submit="save" class={["space-y-4", if(@validating, do: "opacity-50 pointer-events-none")]}>
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
              disabled={@validating}
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 disabled:opacity-50"
            >
              <%= if @validating do %>
                <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" /> Validating...
              <% else %>
                <.icon name="hero-document-check" class="mr-2 size-4" /> Save as Draft
              <% end %>
            </button>
          </form>
        </div>
      <% end %>
    </div>
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
  def handle_event("save", _params, %{assigns: %{validating: true}} = socket) do
    {:noreply, put_flash(socket, :error, "Wait for validation to complete")}
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
           test_code: socket.assigns.test_code,
           template_type: to_string(socket.assigns.generation_result.template),
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

  # --- Streaming handlers ---

  @impl true
  def handle_info({:llm_token, token}, %{assigns: %{generating: true}} = socket) do
    {:noreply, assign(socket, streaming_tokens: socket.assigns.streaming_tokens <> token)}
  end

  @impl true
  def handle_info({:llm_done, full_response}, %{assigns: %{generating: true}} = socket) do
    meta = socket.assigns.generation_meta

    case Pipeline.extract_code(full_response) do
      {:ok, code} ->
        duration_ms = System.monotonic_time(:millisecond) - meta.start_time

        Events.emit_codegen(%{
          duration_ms: duration_ms,
          template_type: meta.template,
          description_length: String.length(socket.assigns.description)
        })

        result = %GenerationResult{
          code: code,
          template: meta.template,
          description: socket.assigns.description,
          provider: meta.provider,
          model: meta.model,
          tokens_used: String.length(full_response),
          output_tokens: String.length(full_response),
          duration_ms: duration_ms
        }

        # Auto-trigger validation pipeline
        lv_pid = self()

        task =
          Task.async(fn ->
            UnifiedPipeline.validate_and_test(code, meta.template,
              progress_callback: fn p -> send(lv_pid, {:pipeline_progress, p}) end,
              token_callback: fn t -> send(lv_pid, {:pipeline_token, t}) end
            )
          end)

        {:noreply,
         assign(socket,
           generating: false,
           generated_code: code,
           generation_result: result,
           streaming_tokens: "",
           save_form: to_form(%{"name" => "", "slug" => ""}),
           generation_meta: nil,
           validating: true,
           pipeline_ref: task.ref,
           pipeline_status: :formatting,
           pipeline_tokens: ""
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           generating: false,
           error: "Could not extract code from LLM response. Please try again.",
           streaming_tokens: "",
           generation_meta: nil
         )}
    end
  end

  @impl true
  def handle_info({:llm_error, reason}, %{assigns: %{generating: true}} = socket) do
    Logger.warning("LLM streaming error: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       generating: false,
       error: "Generation failed. Please try again.",
       streaming_tokens: "",
       generation_meta: nil
     )}
  end

  # Pipeline progress
  @impl true
  def handle_info({:pipeline_progress, progress}, socket) do
    {:noreply, assign(socket, pipeline_status: progress.step)}
  end

  # Pipeline streaming tokens
  @impl true
  def handle_info({:pipeline_token, token}, socket) do
    {:noreply, assign(socket, pipeline_tokens: socket.assigns.pipeline_tokens <> token)}
  end

  # Pipeline completed
  @impl true
  def handle_info({ref, {:ok, %{validation: _} = result}}, socket) when is_reference(ref) do
    if ref == socket.assigns.pipeline_ref do
      Process.demonitor(ref, [:flush])

      {:noreply,
       assign(socket,
         validating: false,
         pipeline_ref: nil,
         pipeline_status: nil,
         pipeline_tokens: "",
         generated_code: result.code,
         test_code: result.test_code,
         validation_report: result.validation
       )}
    else
      {:noreply, socket}
    end
  end

  # Pipeline failed
  @impl true
  def handle_info({ref, {:error, reason}}, socket) when is_reference(ref) do
    if ref == socket.assigns.pipeline_ref do
      Process.demonitor(ref, [:flush])
      Logger.warning("Validation pipeline failed: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(
         validating: false,
         pipeline_ref: nil,
         pipeline_status: nil,
         pipeline_tokens: ""
       )
       |> put_flash(:error, "Validation failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  # Pipeline task crash
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    if ref == socket.assigns[:pipeline_ref] do
      Logger.warning("Validation pipeline crashed: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(validating: false, pipeline_ref: nil, pipeline_status: nil)
       |> put_flash(:error, "Validation pipeline crashed")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Private ---

  defp start_generation(socket, description) do
    scope = socket.assigns.current_scope
    org = scope.organization
    plan = (org && org.plan) || :free

    with :ok <- check_rate_limit(scope, plan),
         :ok <- check_billing_limit(org) do
      start_streaming(socket, description)
    else
      {:error, :rate_limited} ->
        {:noreply,
         assign(socket,
           error: "Rate limit exceeded. Please wait before generating again.",
           show_billing_link: false
         )}

      {:error, :limit_exceeded, details} ->
        {:noreply,
         assign(socket,
           error:
             "You've reached the #{details.plan} plan limit of #{details.limit} LLM generations per month.",
           show_billing_link: true
         )}
    end
  end

  defp check_rate_limit(scope, plan) do
    RateLimiter.check_rate(to_string(scope.user.id), plan)
  end

  defp check_billing_limit(org) do
    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} -> :ok
      {:error, :limit_exceeded, details} -> {:error, :limit_exceeded, details}
    end
  end

  defp start_streaming(socket, description) do
    template = Pipeline.classify_type(description)
    provider = Config.default_provider()
    prompt = Prompts.build_generation_prompt(description, template)
    system = Prompts.system_prompt()

    {:ok, _pid} =
      StreamHandler.start(self(), prompt, model: provider.model, system: system)

    {:noreply,
     assign(socket,
       generating: true,
       error: nil,
       show_billing_link: false,
       description: description,
       generated_code: nil,
       generation_result: nil,
       streaming_tokens: "",
       generation_meta: %{
         template: template,
         provider: to_string(provider.name),
         model: provider.model,
         start_time: System.monotonic_time(:millisecond)
       }
     )}
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
          input_tokens: max(result.tokens_used - result.output_tokens, 0),
          output_tokens: result.output_tokens,
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
