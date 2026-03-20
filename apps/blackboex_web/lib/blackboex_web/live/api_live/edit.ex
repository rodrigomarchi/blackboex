defmodule BlackboexWeb.ApiLive.Edit do
  @moduledoc """
  LiveView for editing API code with Monaco Editor, versioning, and compilation.
  """

  use BlackboexWeb, :live_view

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.Conversations
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Apis.Keys
  alias Blackboex.Apis.Registry
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM
  alias Blackboex.LLM.Config
  alias Blackboex.LLM.EditPrompts
  alias Blackboex.Testing
  alias Blackboex.Testing.RequestExecutor
  alias Blackboex.Testing.ResponseValidator
  alias Blackboex.Testing.SampleData
  alias Blackboex.Testing.SnippetGenerator
  alias Blackboex.Testing.TestGenerator
  alias Blackboex.Testing.TestRunner

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org = resolve_organization(socket, params)

    case org && Apis.get_api(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "API not found")
         |> push_navigate(to: ~p"/apis")}

      api ->
        # Authorization: resolve_organization already verified membership.
        # org is nil if user has no membership → api lookup returns nil → redirected above.
        versions = Apis.list_versions(api.id)
        {:ok, conversation} = Conversations.get_or_create_conversation(api.id)

        {:ok,
         assign(socket,
           api: api,
           org: org,
           code: api.source_code || "",
           page_title: "Edit: #{api.name}",
           compile_errors: nil,
           compile_success: false,
           saving: false,
           tab: "info",
           versions: versions,
           selected_version: nil,
           diff_old: nil,
           diff_new: nil,
           chat_messages: conversation.messages,
           chat_input: "",
           chat_loading: false,
           chat_conversation: conversation,
           pending_edit: nil,
           # Test tab assigns
           test_method: api.method || "GET",
           test_url: "/api/#{org.slug}/#{api.slug}",
           test_params: [],
           test_headers: [
             %{key: "Content-Type", value: "application/json", id: Ecto.UUID.generate()}
           ],
           test_body_json: default_test_body(api),
           test_body_error: nil,
           test_api_key: "",
           test_response: nil,
           test_loading: false,
           test_error: nil,
           test_violations: [],
           test_history: [],
           history_loaded: false,
           request_tab: "body",
           response_tab: "body",
           test_ref: nil,
           # Auto-test assigns
           auto_test_code: nil,
           auto_test_results: [],
           auto_test_suites: [],
           auto_test_suites_loaded: false,
           test_generating: false,
           test_running: false,
           test_gen_ref: nil,
           test_run_ref: nil,
           expanded_test: nil,
           doc_generating: false,
           doc_gen_ref: nil,
           # Publish assigns
           api_keys: [],
           keys_loaded: false,
           plain_key_flash: nil,
           metrics: nil
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">{@api.name}</h1>
            <p class="text-sm text-muted-foreground">{@api.description}</p>
          </div>
          <div class="flex items-center gap-2">
            <span class={[
              "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
              status_color(@api.status)
            ]}>
              {@api.status}
            </span>
            <.link
              navigate={~p"/apis/#{@api.id}"}
              class="text-sm text-muted-foreground hover:text-foreground"
            >
              Back
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-12 gap-4">
          <%!-- Chat Panel (25%) --%>
          <div class="col-span-3 rounded-lg border bg-card text-card-foreground shadow-sm max-h-[700px]">
            <.live_component
              module={BlackboexWeb.Components.ChatPanel}
              id="chat-panel"
              messages={@chat_messages}
              input={@chat_input}
              loading={@chat_loading}
              api_id={@api.id}
              pending_edit={@pending_edit}
              template_type={@api.template_type}
            />
          </div>

          <%!-- Editor Panel (50%) — hidden when Test tab active --%>
          <div class={[
            "col-span-6 rounded-lg border bg-card text-card-foreground shadow-sm",
            if(@tab == "test", do: "hidden")
          ]}>
            <div class="flex items-center justify-between border-b px-4 py-2">
              <h2 class="text-sm font-semibold">Code Editor</h2>
              <div class="flex items-center gap-2">
                <button
                  phx-click="save"
                  disabled={@saving}
                  class="inline-flex items-center rounded-md border px-3 py-1 text-xs font-medium hover:bg-accent"
                >
                  Save
                </button>
                <button
                  phx-click="save_and_compile"
                  class="inline-flex items-center rounded-md bg-primary px-3 py-1 text-xs font-medium text-primary-foreground hover:bg-primary/90"
                >
                  Save & Compile
                </button>
              </div>
            </div>
            <div style="min-height: 500px;">
              <LiveMonacoEditor.code_editor
                path={"api_#{@api.id}.ex"}
                value={@code}
                change="code_changed"
                style="min-height: 500px; width: 100%;"
                opts={
                  Map.merge(LiveMonacoEditor.default_opts(), %{
                    "language" => "elixir",
                    "fontSize" => 14,
                    "minimap" => %{"enabled" => false},
                    "wordWrap" => "on",
                    "scrollBeyondLastLine" => false,
                    "readOnly" => @selected_version != nil
                  })
                }
              />
            </div>
          </div>

          <%!-- Test Panel (50%) — shown when Test tab active --%>
          <%= if @tab == "test" do %>
            <div
              class="col-span-6 space-y-4"
              phx-window-keydown="keyboard_shortcut"
              phx-key="Enter"
            >
              <.live_component
                module={BlackboexWeb.Components.RequestBuilder}
                id="request-builder"
                method={@test_method}
                url={@test_url}
                params={@test_params}
                headers={@test_headers}
                body_json={@test_body_json}
                body_error={@test_body_error}
                api_key={@test_api_key}
                loading={@test_loading}
                active_tab={@request_tab}
              />

              <.live_component
                module={BlackboexWeb.Components.ResponseViewer}
                id="response-viewer"
                response={@test_response}
                loading={@test_loading}
                error={@test_error}
                violations={@test_violations}
                response_tab={@response_tab}
              />
            </div>
          <% end %>

          <%!-- Side Panel (25%) --%>
          <div class="col-span-3 space-y-4">
            <%!-- Tabs --%>
            <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
              <div class="flex border-b">
                <button
                  :for={t <- ["info", "versions", "test", "auto_tests", "keys", "publish"]}
                  phx-click="switch_tab"
                  phx-value-tab={t}
                  class={[
                    "flex-1 px-3 py-2 text-xs font-medium border-b-2",
                    if(t == @tab,
                      do: "border-primary text-primary",
                      else: "border-transparent text-muted-foreground hover:text-foreground"
                    )
                  ]}
                >
                  {tab_label(t)}
                </button>
              </div>

              <div class="p-4">
                {render_tab(assigns)}
              </div>
            </div>

            <%!-- Compile Errors --%>
            <%= if @compile_errors do %>
              <div class="rounded-lg border border-destructive bg-destructive/10 p-3 text-xs text-destructive space-y-1">
                <p class="font-semibold">Compilation failed:</p>
                <ul class="list-disc list-inside">
                  <%= for error <- @compile_errors do %>
                    <li>{error}</li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%= if @compile_success do %>
              <div class="rounded-lg border border-green-500 bg-green-50 p-3 text-xs text-green-700">
                Compiled successfully. API available at
                <code class="font-mono">/api/{@org.slug}/{@api.slug}</code>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_tab(%{tab: "info"} = assigns) do
    ~H"""
    <div class="space-y-3 text-sm">
      <div>
        <span class="text-muted-foreground">Name:</span>
        <span class="font-medium ml-1">{@api.name}</span>
      </div>
      <div>
        <span class="text-muted-foreground">Slug:</span>
        <code class="ml-1">{@api.slug}</code>
      </div>
      <div>
        <span class="text-muted-foreground">Template:</span>
        <span class="ml-1">{@api.template_type}</span>
      </div>
      <div>
        <span class="text-muted-foreground">Status:</span>
        <span class="ml-1">{@api.status}</span>
      </div>
      <%= if @api.status in ["compiled", "published"] do %>
        <div>
          <span class="text-muted-foreground">URL:</span>
          <code class="ml-1">/api/{@org.slug}/{@api.slug}</code>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "versions"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @selected_version do %>
        <button
          phx-click="clear_version_view"
          class="text-xs text-primary hover:underline mb-2"
        >
          Back to current code
        </button>
      <% end %>

      <%= if @versions == [] do %>
        <p class="text-sm text-muted-foreground">
          No versions yet. Save to create the first version.
        </p>
      <% else %>
        <%= for version <- @versions do %>
          <div class={[
            "rounded border p-2 text-xs space-y-1",
            if(@selected_version && @selected_version.id == version.id,
              do: "border-primary bg-primary/5",
              else: ""
            )
          ]}>
            <div class="flex items-center justify-between">
              <span class="font-semibold">v{version.version_number}</span>
              <span class="text-muted-foreground">
                {Calendar.strftime(version.inserted_at, "%H:%M")}
              </span>
            </div>
            <div class="text-muted-foreground">
              {version.source}
              <%= if version.diff_summary do %>
                — {version.diff_summary}
              <% end %>
            </div>
            <div class="flex gap-1">
              <button
                phx-click="view_version"
                phx-value-number={version.version_number}
                class="text-primary hover:underline"
              >
                View
              </button>
              <%= if version.version_number != hd(@versions).version_number do %>
                <button
                  phx-click="rollback"
                  phx-value-number={version.version_number}
                  class="text-orange-600 hover:underline"
                  data-confirm={"Rollback to v#{version.version_number}? This creates a new version."}
                >
                  Restore
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "test"} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="text-xs font-semibold text-muted-foreground uppercase">Quick Actions</h3>
      <div class="space-y-1">
        <button
          phx-click="quick_test"
          phx-value-method="GET"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Testar GET /
        </button>
        <button
          phx-click="quick_test"
          phx-value-method="POST"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Testar POST / com exemplo
        </button>
        <button
          phx-click="generate_sample"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Gerar dados de exemplo
        </button>
      </div>

      <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-4">Snippets</h3>
      <div class="flex flex-wrap gap-1">
        <button
          :for={lang <- ~w(curl python javascript elixir ruby go)}
          phx-click="copy_snippet"
          phx-value-language={lang}
          class="rounded border px-2 py-0.5 text-xs hover:bg-accent"
        >
          {lang}
        </button>
      </div>

      <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-4">History</h3>
      <%= if @test_history == [] do %>
        <p class="text-xs text-muted-foreground">No requests yet</p>
      <% else %>
        <div class="space-y-1 max-h-60 overflow-y-auto">
          <div
            :for={item <- @test_history}
            phx-click="load_history_item"
            phx-value-id={item.id}
            class="rounded border p-1.5 text-xs cursor-pointer hover:bg-accent flex items-center justify-between"
          >
            <div class="flex items-center gap-1">
              <span class="font-semibold">{item.method}</span>
              <span class="text-muted-foreground truncate max-w-[100px]">{item.path}</span>
            </div>
            <div class="flex items-center gap-1">
              <span class={[
                "inline-flex rounded-full px-1 py-0.5 text-[10px] font-semibold",
                history_status_color(item.response_status)
              ]}>
                {item.response_status}
              </span>
              <span class="text-muted-foreground">{item.duration_ms}ms</span>
            </div>
          </div>
        </div>
        <button
          phx-click="clear_history"
          class="text-xs text-destructive hover:underline"
          data-confirm="Limpar histórico de requests?"
        >
          Limpar histórico
        </button>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "auto_tests"} = assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-xs font-semibold text-muted-foreground uppercase">Auto Tests</h3>
        <%= if @auto_test_results != [] do %>
          <span class={[
            "inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold",
            auto_test_badge_color(@auto_test_results)
          ]}>
            {test_pass_count(@auto_test_results)}/{length(@auto_test_results)} passing
          </span>
        <% end %>
      </div>

      <%!-- Generate / Regenerate buttons --%>
      <div class="space-y-1">
        <%= if @auto_test_code do %>
          <button
            phx-click="regenerate_tests"
            disabled={@test_generating}
            class="w-full rounded border px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
          >
            {if @test_generating, do: "Generating...", else: "Regenerate Tests"}
          </button>
          <button
            phx-click="run_tests"
            disabled={@test_running}
            class="w-full rounded bg-primary px-2 py-1 text-xs text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          >
            {if @test_running, do: "Running...", else: "Run Tests"}
          </button>
        <% else %>
          <button
            phx-click="generate_tests"
            disabled={@test_generating}
            class="w-full rounded bg-primary px-2 py-1 text-xs text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          >
            {if @test_generating, do: "Generating...", else: "Generate Tests"}
          </button>
        <% end %>
      </div>

      <%!-- Test Results --%>
      <%= if @auto_test_results != [] do %>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-2">Results</h3>
        <div class="space-y-1 max-h-60 overflow-y-auto">
          <div :for={result <- @auto_test_results} class="rounded border p-1.5 text-xs space-y-1">
            <div
              class="flex items-center justify-between cursor-pointer"
              phx-click="toggle_test_result"
              phx-value-name={result.name}
            >
              <div class="flex items-center gap-1">
                <span class={if result.status == "passed", do: "text-green-600", else: "text-red-600"}>
                  {if result.status == "passed", do: "✓", else: "✗"}
                </span>
                <span class="truncate max-w-[180px]">{result.name}</span>
              </div>
              <span class="text-muted-foreground">{result.duration_ms}ms</span>
            </div>
            <%= if @expanded_test == result.name and result.error do %>
              <div class="mt-1 rounded bg-red-50 p-2 text-[10px] font-mono text-red-700 whitespace-pre-wrap">
                {result.error}
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- History --%>
      <%= if @auto_test_suites != [] do %>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-2">History</h3>
        <div class="space-y-1 max-h-40 overflow-y-auto">
          <div :for={suite <- @auto_test_suites} class="rounded border p-1.5 text-xs">
            <div class="flex items-center justify-between">
              <span class={[
                "inline-flex rounded-full px-1.5 py-0.5 text-[10px] font-semibold",
                suite_status_color(suite.status)
              ]}>
                {suite.status}
              </span>
              <span class="text-muted-foreground">
                {suite.passed_tests}/{suite.total_tests}
              </span>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "keys"} = assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-xs font-semibold text-muted-foreground uppercase">API Keys</h3>
        <button
          phx-click="create_key"
          class="rounded bg-primary px-2 py-1 text-xs text-primary-foreground hover:bg-primary/90"
        >
          New Key
        </button>
      </div>

      <%= if @plain_key_flash do %>
        <div class="rounded border border-amber-500 bg-amber-50 p-2 text-xs space-y-1">
          <p class="font-semibold text-amber-800">Copy this key now — it won't be shown again:</p>
          <code class="block bg-white p-1 rounded font-mono text-xs break-all select-all">
            {@plain_key_flash}
          </code>
          <button
            phx-click="dismiss_key_flash"
            class="text-amber-600 hover:underline text-[10px]"
          >
            Dismiss
          </button>
        </div>
      <% end %>

      <%= if @api_keys == [] do %>
        <p class="text-xs text-muted-foreground">No keys yet</p>
      <% else %>
        <div class="space-y-1">
          <div :for={key <- @api_keys} class="rounded border p-2 text-xs space-y-1">
            <div class="flex items-center justify-between">
              <code class="font-mono text-muted-foreground">{key.key_prefix}...</code>
              <span class={[
                "rounded-full px-1.5 py-0.5 text-[10px] font-semibold",
                if(key.revoked_at, do: "bg-red-100 text-red-700", else: "bg-green-100 text-green-700")
              ]}>
                {if key.revoked_at, do: "Revoked", else: "Active"}
              </span>
            </div>
            <p :if={key.label} class="text-muted-foreground">{key.label}</p>
            <div class="flex gap-2">
              <button
                :if={!key.revoked_at}
                phx-click="revoke_key"
                phx-value-key-id={key.id}
                data-confirm="Revoke this key? This cannot be undone."
                class="text-destructive hover:underline text-[10px]"
              >
                Revoke
              </button>
              <button
                :if={!key.revoked_at}
                phx-click="rotate_key"
                phx-value-key-id={key.id}
                data-confirm="Rotate this key? The old key will be revoked immediately."
                class="text-blue-600 hover:underline text-[10px]"
              >
                Rotate
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "publish"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <h3 class="text-xs font-semibold text-muted-foreground uppercase">Publishing</h3>

      <div class="space-y-2 text-xs">
        <div>
          <span class="text-muted-foreground">Status:</span>
          <span class={[
            "inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold ml-1",
            status_color(@api.status)
          ]}>
            {@api.status}
          </span>
        </div>
        <div>
          <span class="text-muted-foreground">URL:</span>
          <code class="ml-1 font-mono">/api/{@org.slug}/{@api.slug}</code>
        </div>
      </div>

      <%= if @api.status == "compiled" do %>
        <button
          phx-click="publish"
          class="w-full rounded bg-blue-600 px-3 py-2 text-xs font-medium text-white hover:bg-blue-700"
        >
          Publish API
        </button>
      <% end %>

      <%= if @api.status == "published" do %>
        <div class="space-y-2">
          <div class="rounded border border-green-200 bg-green-50 p-2 text-xs text-green-700">
            API is live at <code class="font-mono">/api/{@org.slug}/{@api.slug}</code>
          </div>

          <%= if @metrics do %>
            <div class="grid grid-cols-3 gap-2">
              <div class="rounded border p-2 text-center">
                <p class="text-lg font-bold">{@metrics.count_24h}</p>
                <p class="text-[10px] text-muted-foreground">24h calls</p>
              </div>
              <div class="rounded border p-2 text-center">
                <p class="text-lg font-bold">{@metrics.success_rate}%</p>
                <p class="text-[10px] text-muted-foreground">Success</p>
              </div>
              <div class="rounded border p-2 text-center">
                <p class="text-lg font-bold">{@metrics.avg_latency}ms</p>
                <p class="text-[10px] text-muted-foreground">Avg latency</p>
              </div>
            </div>
          <% end %>

          <button
            phx-click="unpublish"
            data-confirm="Unpublish this API? It will no longer be accessible."
            class="w-full rounded border border-destructive px-3 py-2 text-xs font-medium text-destructive hover:bg-destructive/10"
          >
            Unpublish
          </button>
        </div>
      <% end %>

      <%= if @api.status == "draft" do %>
        <p class="text-xs text-muted-foreground">
          Compile the API first before publishing.
        </p>
      <% end %>

      <%!-- Documentation Generation --%>
      <%= if @api.status in ["compiled", "published"] do %>
        <div class="border-t pt-3 mt-3">
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-2">Documentation</h3>
          <button
            phx-click="generate_docs"
            disabled={@doc_generating}
            class="w-full rounded border px-3 py-1.5 text-xs font-medium hover:bg-accent disabled:opacity-50"
          >
            {if @doc_generating,
              do: "Generating...",
              else: if(@api.documentation_md, do: "Regenerate Docs", else: "Generate Docs")}
          </button>
          <%= if @api.documentation_md do %>
            <p class="text-[10px] text-green-600 mt-1">Documentation available on public page</p>
          <% end %>

          <%= if @api.status == "published" and @api.visibility == "public" do %>
            <a
              href={"/api/#{@org.slug}/#{@api.slug}/docs"}
              target="_blank"
              class="block text-xs text-primary hover:underline mt-1"
            >
              View Swagger UI
            </a>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("code_changed", %{"value" => new_code}, socket) do
    {:noreply,
     assign(socket,
       code: new_code,
       selected_version: nil,
       compile_success: false,
       compile_errors: nil
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> lazy_load_tab(tab) |> assign(tab: tab)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    save_version(socket, false)
  end

  @impl true
  def handle_event("save_and_compile", _params, socket) do
    save_version(socket, true)
  end

  @impl true
  def handle_event("publish", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Apis.publish(api, org) do
      {:ok, published_api, plain_key} ->
        {:noreply,
         socket
         |> assign(api: published_api, plain_key_flash: plain_key, tab: "keys")
         |> assign(api_keys: Keys.list_keys(published_api.id), keys_loaded: true)
         |> put_flash(:info, "API published successfully")}

      {:error, :not_compiled} ->
        {:noreply, put_flash(socket, :error, "API must be compiled before publishing")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to publish API")}
    end
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    case Apis.unpublish(socket.assigns.api) do
      {:ok, updated_api} ->
        {:noreply,
         socket
         |> assign(api: updated_api)
         |> put_flash(:info, "API unpublished")}

      {:error, :not_published} ->
        {:noreply, put_flash(socket, :error, "API is not published")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish API")}
    end
  end

  @impl true
  def handle_event("create_key", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Keys.create_key(api, %{label: "API Key", organization_id: org.id}) do
      {:ok, plain_key, _api_key} ->
        keys = Keys.list_keys(api.id)
        {:noreply, assign(socket, api_keys: keys, plain_key_flash: plain_key)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create key")}
    end
  end

  @impl true
  def handle_event("revoke_key", %{"key-id" => key_id}, socket) do
    %{api: api, api_keys: api_keys} = socket.assigns
    # IDOR protection: verify key belongs to this API by matching api_id
    key = Enum.find(api_keys, &(&1.id == key_id and &1.api_id == api.id))

    if key do
      case Keys.revoke_key(key) do
        {:ok, _} ->
          keys = Keys.list_keys(api.id)
          {:noreply, assign(socket, api_keys: keys)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to revoke key")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rotate_key", %{"key-id" => key_id}, socket) do
    %{api: api, api_keys: api_keys} = socket.assigns
    # IDOR protection: verify key belongs to this API by matching api_id
    key = Enum.find(api_keys, &(&1.id == key_id and &1.api_id == api.id))

    if key do
      case Keys.rotate_key(key) do
        {:ok, plain_key, _new_key} ->
          keys = Keys.list_keys(api.id)
          {:noreply, assign(socket, api_keys: keys, plain_key_flash: plain_key)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to rotate key")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_key_flash", _params, socket) do
    {:noreply, assign(socket, plain_key_flash: nil)}
  end

  @impl true
  def handle_event("view_version", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    version = Apis.get_version(socket.assigns.api.id, number)

    if version do
      {:noreply,
       socket
       |> assign(code: version.code, selected_version: version)
       |> push_editor_value(version.code)}
    else
      {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  @impl true
  def handle_event("clear_version_view", _params, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    code = api.source_code || ""

    {:noreply,
     socket
     |> assign(code: code, selected_version: nil, api: api)
     |> push_editor_value(code)}
  end

  @impl true
  def handle_event("rollback", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    api = socket.assigns.api
    scope = socket.assigns.current_scope

    case Apis.rollback_to_version(api, number, scope.user.id) do
      {:ok, new_version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)

        # Recompile after rollback
        compile_result = compile_api(api, socket.assigns.org)

        {:noreply,
         socket
         |> assign(
           api: api,
           code: new_version.code,
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           compile_errors: compile_result.errors,
           compile_success: compile_result.success
         )
         |> push_editor_value(new_version.code)
         |> put_flash(:info, "Rolled back to v#{number}")}

      {:error, :version_not_found} ->
        {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  # --- Test Tab Events ---

  @valid_methods ~w(GET POST PUT PATCH DELETE)
  @valid_request_tabs ~w(params headers body auth)
  @valid_response_tabs ~w(body headers)
  @valid_snippet_languages ~w(curl python javascript elixir ruby go)

  @impl true
  def handle_event("update_test_method", %{"method" => method}, socket)
      when method in @valid_methods do
    {:noreply, assign(socket, test_method: method)}
  end

  def handle_event("update_test_method", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_test_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, test_url: url)}
  end

  @impl true
  def handle_event("switch_request_tab", %{"tab" => tab}, socket)
      when tab in @valid_request_tabs do
    {:noreply, assign(socket, request_tab: tab)}
  end

  def handle_event("switch_request_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_response_tab", %{"tab" => tab}, socket)
      when tab in @valid_response_tabs do
    {:noreply, assign(socket, response_tab: tab)}
  end

  def handle_event("switch_response_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_test_body", %{"test_body_json" => body}, socket) do
    body_error =
      case Jason.decode(body) do
        {:ok, _} -> nil
        {:error, _} -> "Invalid JSON"
      end

    {:noreply, assign(socket, test_body_json: body, test_body_error: body_error)}
  end

  @impl true
  def handle_event("update_test_api_key", %{"test_api_key" => key}, socket) do
    {:noreply, assign(socket, test_api_key: key)}
  end

  @impl true
  def handle_event("add_param", _params, socket) do
    new_param = %{key: "", value: "", id: Ecto.UUID.generate()}
    {:noreply, assign(socket, test_params: socket.assigns.test_params ++ [new_param])}
  end

  @impl true
  def handle_event("remove_param", %{"id" => id}, socket) do
    params = Enum.reject(socket.assigns.test_params, &(&1.id == id))
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("update_param_key", %{"id" => id, "param_key" => key}, socket) do
    params = update_item(socket.assigns.test_params, id, :key, key)
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("update_param_value", %{"id" => id, "param_value" => value}, socket) do
    params = update_item(socket.assigns.test_params, id, :value, value)
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("add_header", _params, socket) do
    new_header = %{key: "", value: "", id: Ecto.UUID.generate()}
    {:noreply, assign(socket, test_headers: socket.assigns.test_headers ++ [new_header])}
  end

  @impl true
  def handle_event("remove_header", %{"id" => id}, socket) do
    headers = Enum.reject(socket.assigns.test_headers, &(&1.id == id))
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("update_header_key", %{"id" => id, "header_key" => key}, socket) do
    headers = update_item(socket.assigns.test_headers, id, :key, key)
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("update_header_value", %{"id" => id, "header_value" => value}, socket) do
    headers = update_item(socket.assigns.test_headers, id, :value, value)
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("keyboard_shortcut", %{"key" => "Enter", "ctrlKey" => true}, socket) do
    handle_event("send_request", %{}, socket)
  end

  def handle_event("keyboard_shortcut", %{"key" => "Enter", "metaKey" => true}, socket) do
    handle_event("send_request", %{}, socket)
  end

  def handle_event("keyboard_shortcut", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_request", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send_request", _params, socket) do
    request = build_request(socket.assigns)

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply, assign(socket, test_loading: true, test_error: nil, test_ref: task.ref)}
  end

  @impl true
  def handle_event("quick_test", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("quick_test", %{"method" => method}, socket)
      when method in @valid_methods do
    body =
      if method == "POST" do
        sample = SampleData.generate(socket.assigns.api)
        Jason.encode!(sample.happy_path)
      else
        socket.assigns.test_body_json
      end

    socket = assign(socket, test_method: method, test_body_json: body)
    request = build_request(socket.assigns)

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply, assign(socket, test_loading: true, test_error: nil, test_ref: task.ref)}
  end

  @impl true
  def handle_event("generate_sample", _params, socket) do
    sample = SampleData.generate(socket.assigns.api)
    body = Jason.encode!(sample.happy_path, pretty: true)
    {:noreply, assign(socket, test_body_json: body, test_body_error: nil, request_tab: "body")}
  end

  @impl true
  def handle_event("copy_snippet", %{"language" => lang}, socket)
      when lang in @valid_snippet_languages do
    request = %{
      method: socket.assigns.test_method,
      url: "http://localhost:4000#{socket.assigns.test_url}",
      headers: build_header_list(socket.assigns.test_headers),
      body: socket.assigns.test_body_json,
      api_key: if(socket.assigns.test_api_key != "", do: socket.assigns.test_api_key, else: nil)
    }

    snippet =
      SnippetGenerator.generate(socket.assigns.api, String.to_atom(lang), request)

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: snippet})
     |> put_flash(:info, "Snippet #{lang} copiado!")}
  end

  def handle_event("copy_snippet", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load_history_item", %{"id" => id}, socket) do
    api_id = socket.assigns.api.id

    case Testing.get_test_request(id) do
      {:ok, %{api_id: ^api_id} = item} ->
        headers =
          Enum.map(item.headers || %{}, fn {k, v} ->
            %{key: k, value: v, id: Ecto.UUID.generate()}
          end)

        response = %{
          status: item.response_status,
          headers: item.response_headers || %{},
          body: item.response_body || "",
          duration_ms: item.duration_ms
        }

        {:noreply,
         assign(socket,
           test_method: item.method,
           test_headers: headers,
           test_body_json: item.body || "{}",
           test_response: response,
           test_violations: validate_response(response, socket.assigns.api),
           response_tab: "body"
         )}

      {:ok, _item} ->
        {:noreply, put_flash(socket, :error, "Request not found")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Request not found")}
    end
  end

  @impl true
  def handle_event("clear_history", _params, socket) do
    Testing.clear_history(socket.assigns.api.id)
    {:noreply, assign(socket, test_history: [])}
  end

  # --- Chat Events ---

  @impl true
  def handle_event("send_chat", %{"chat_input" => ""}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_chat", %{"chat_input" => message}, socket) do
    conversation = socket.assigns.chat_conversation

    # Persist user message
    case Conversations.append_message(conversation, "user", message) do
      {:ok, conversation} ->
        do_chat_request(socket, conversation, message)

      {:error, :too_many_messages} ->
        {:noreply, put_flash(socket, :error, friendly_llm_error(:too_many_messages))}

      {:error, reason} ->
        Logger.warning("Failed to append user message: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Falha ao enviar mensagem")}
    end
  end

  @impl true
  def handle_event("accept_edit", _params, socket) do
    case socket.assigns.pending_edit do
      nil ->
        {:noreply, socket}

      %{code: proposed_code, instruction: instruction} ->
        scope = socket.assigns.current_scope

        case Apis.create_version(socket.assigns.api, %{
               code: proposed_code,
               source: "chat_edit",
               prompt: instruction,
               created_by_id: scope.user.id
             }) do
          {:ok, _version} ->
            api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

            {:noreply,
             socket
             |> assign(
               api: api,
               code: proposed_code,
               versions: Apis.list_versions(api.id),
               pending_edit: nil
             )
             |> push_editor_value(proposed_code)
             |> put_flash(:info, "Mudança aceita e versão criada")}

          {:error, changeset} ->
            Logger.error("Failed to create chat_edit version: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Falha ao criar versão")}
        end
    end
  end

  @impl true
  def handle_event("reject_edit", _params, socket) do
    {:noreply, assign(socket, pending_edit: nil)}
  end

  @impl true
  def handle_event("quick_action", %{"text" => text}, socket) do
    {:noreply, assign(socket, chat_input: text)}
  end

  @impl true
  def handle_event("clear_conversation", _params, socket) do
    conversation = socket.assigns.chat_conversation

    case Conversations.clear_conversation(conversation) do
      {:ok, cleared} ->
        {:noreply,
         assign(socket,
           chat_conversation: cleared,
           chat_messages: [],
           pending_edit: nil
         )}

      {:error, changeset} ->
        Logger.error("Failed to clear conversation: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Falha ao limpar conversa")}
    end
  end

  @impl true
  def handle_event("generate_tests", _params, %{assigns: %{test_generating: true}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_tests", _params, socket) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        task = Task.async(fn -> TestGenerator.generate_tests(api) end)
        {:noreply, assign(socket, test_generating: true, test_gen_ref: task.ref)}

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  @impl true
  def handle_event("regenerate_tests", _params, socket) do
    handle_event("generate_tests", %{}, socket)
  end

  @impl true
  def handle_event("run_tests", _params, %{assigns: %{test_running: true}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("run_tests", _params, socket) do
    code = socket.assigns.auto_test_code

    if code do
      task = Task.async(fn -> TestRunner.run(code) end)
      {:noreply, assign(socket, test_running: true, test_run_ref: task.ref)}
    else
      {:noreply, put_flash(socket, :error, "No test code to run")}
    end
  end

  @impl true
  def handle_event("toggle_test_result", %{"name" => name}, socket) do
    expanded = if socket.assigns.expanded_test == name, do: nil, else: name
    {:noreply, assign(socket, expanded_test: expanded)}
  end

  @impl true
  def handle_event("generate_docs", _params, %{assigns: %{doc_generating: true}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_docs", _params, socket) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        task = Task.async(fn -> DocGenerator.generate(api) end)
        {:noreply, assign(socket, doc_generating: true, doc_gen_ref: task.ref)}

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  # --- Helpers ---

  defp do_chat_request(socket, conversation, message) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        do_chat_llm_call(socket, conversation, message)

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  defp do_chat_llm_call(socket, conversation, message) do
    socket =
      socket
      |> assign(
        chat_conversation: conversation,
        chat_messages: conversation.messages,
        chat_loading: true,
        chat_input: ""
      )

    prompt =
      EditPrompts.build_edit_prompt(
        socket.assigns.code,
        message,
        conversation.messages
      )

    case Config.client().generate_text(prompt, system: EditPrompts.system_prompt()) do
      {:ok, %{content: response} = llm_response} ->
        record_chat_usage(socket, llm_response)
        handle_llm_response(socket, conversation, response, message)

      {:error, reason} ->
        Logger.warning("LLM chat error for API #{socket.assigns.api.id}: #{inspect(reason)}")

        error_msg = friendly_llm_error(reason)

        {:ok, conversation} =
          Conversations.append_message(conversation, "assistant", error_msg)

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false
         )}
    end
  end

  defp record_chat_usage(socket, llm_response) do
    scope = socket.assigns.current_scope
    usage = Map.get(llm_response, :usage, %{})
    provider = Config.default_provider()

    LLM.record_usage(%{
      user_id: scope.user.id,
      organization_id: socket.assigns.org.id,
      provider: to_string(provider.name),
      model: provider.model,
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      cost_cents: 0,
      operation: "chat_edit",
      api_id: socket.assigns.api.id,
      duration_ms: 0
    })
  end

  defp save_version(socket, compile?) do
    api = socket.assigns.api
    scope = socket.assigns.current_scope
    code = socket.assigns.code

    # Fix 5: Skip save if code hasn't changed
    if code == (api.source_code || "") and not compile? do
      {:noreply, put_flash(socket, :info, "No changes to save")}
    else
      do_save_version(socket, api, scope, code, compile?)
    end
  end

  defp do_save_version(socket, api, scope, code, compile?) do
    case Apis.create_version(api, %{
           code: code,
           source: "manual_edit",
           created_by_id: scope.user.id
         }) do
      {:ok, version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)

        compile_result =
          if compile?,
            do: compile_api(api, socket.assigns.org),
            else: %{success: false, errors: nil}

        if compile?, do: update_version_status(version, compile_result)

        {:noreply,
         socket
         |> assign(
           api: api,
           versions: Apis.list_versions(api.id),
           compile_errors: compile_result.errors,
           compile_success: compile_result.success
         )
         |> put_flash(
           :info,
           if(compile? && compile_result.success, do: "Saved & compiled", else: "Saved")
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  defp update_version_status(version, compile_result) do
    alias Blackboex.Apis.ApiVersion

    status = if compile_result.success, do: "success", else: "error"
    errors = compile_result.errors || []

    Blackboex.Repo.update(
      ApiVersion.changeset(version, %{compilation_status: status, compilation_errors: errors})
    )
  end

  defp compile_api(api, org) do
    case Compiler.compile(api, api.source_code) do
      {:ok, module} ->
        Apis.update_api(api, %{status: "compiled"})

        try do
          Registry.register(api.id, module, org_slug: org.slug, slug: api.slug)
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

        %{success: true, errors: nil}

      {:error, {:validation, reasons}} ->
        %{success: false, errors: reasons}

      {:error, {:compilation, reason}} ->
        %{success: false, errors: [reason]}
    end
  end

  # --- Task.async result handlers ---

  @impl true
  def handle_info({ref, result}, %{assigns: %{test_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        violations = validate_response(response, socket.assigns.api)

        # Persist to history
        scope = socket.assigns.current_scope

        Testing.create_test_request(%{
          api_id: socket.assigns.api.id,
          user_id: scope.user.id,
          method: socket.assigns.test_method,
          path: socket.assigns.test_url,
          headers: headers_to_persist(socket.assigns),
          body: socket.assigns.test_body_json,
          response_status: response.status,
          response_headers: response.headers,
          response_body: response.body,
          duration_ms: response.duration_ms
        })

        history = Testing.list_test_requests(socket.assigns.api.id)

        {:noreply,
         assign(socket,
           test_response: response,
           test_loading: false,
           test_error: nil,
           test_violations: violations,
           test_history: history,
           response_tab: "body",
           test_ref: nil
         )}

      {:error, :forbidden} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "URL não permitida. Apenas /api/{username}/{slug}/* é aceito."
         )}

      {:error, :timeout} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Timeout: a requisição demorou demais."
         )}

      {:error, reason} ->
        Logger.warning("Test request failed: #{inspect(reason)}")

        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Erro de conexão. Verifique se a API está compilada."
         )}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{test_ref: ref}} = socket) do
    {:noreply, assign(socket, test_loading: false, test_ref: nil)}
  end

  @impl true
  def handle_info(
        {ref, {:ok, %{code: test_code, usage: usage}}},
        %{assigns: %{test_gen_ref: ref}} = socket
      ) do
    Process.demonitor(ref, [:flush])
    record_generation_usage(socket, "test_generation", usage)

    {:noreply,
     socket
     |> assign(
       auto_test_code: test_code,
       test_generating: false,
       test_gen_ref: nil,
       auto_test_results: []
     )
     |> put_flash(:info, "Tests generated successfully")}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, %{assigns: %{test_gen_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])
    Logger.warning("Test generation failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(test_generating: false, test_gen_ref: nil)
     |> put_flash(:error, "Failed to generate tests. Please try again.")}
  end

  @impl true
  def handle_info({ref, {:ok, results}}, %{assigns: %{test_run_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    passed = Enum.count(results, &(&1.status == "passed"))
    failed = length(results) - passed
    total_duration = results |> Enum.map(& &1.duration_ms) |> Enum.sum()

    serializable_results =
      Enum.map(results, fn r ->
        %{
          "name" => r.name,
          "status" => r.status,
          "duration_ms" => r.duration_ms,
          "error" => r.error
        }
      end)

    {:ok, suite} =
      Testing.create_test_suite(%{
        api_id: socket.assigns.api.id,
        test_code: socket.assigns.auto_test_code,
        status: if(failed == 0, do: "passed", else: "failed"),
        results: serializable_results,
        total_tests: length(results),
        passed_tests: passed,
        failed_tests: failed,
        duration_ms: total_duration
      })

    suites = [suite | socket.assigns.auto_test_suites] |> Enum.take(10)

    {:noreply,
     socket
     |> assign(
       test_running: false,
       test_run_ref: nil,
       auto_test_results: results,
       auto_test_suites: suites
     )
     |> put_flash(:info, "Tests completed: #{passed}/#{length(results)} passing")}
  end

  @impl true
  def handle_info({ref, {:error, :compile_error, msg}}, %{assigns: %{test_run_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])
    Logger.warning("Test run compile error: #{msg}")

    {:noreply,
     socket
     |> assign(test_running: false, test_run_ref: nil)
     |> put_flash(:error, "Test code has compilation errors")}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, %{assigns: %{test_run_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])
    Logger.warning("Test run failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(test_running: false, test_run_ref: nil)
     |> put_flash(:error, "Test execution failed")}
  end

  @impl true
  def handle_info(
        {ref, {:ok, %{doc: markdown, usage: usage}}},
        %{assigns: %{doc_gen_ref: ref}} = socket
      ) do
    Process.demonitor(ref, [:flush])
    record_generation_usage(socket, "doc_generation", usage)

    case Apis.update_api(socket.assigns.api, %{documentation_md: markdown}) do
      {:ok, updated_api} ->
        {:noreply,
         socket
         |> assign(api: updated_api, doc_generating: false, doc_gen_ref: nil)
         |> put_flash(:info, "Documentation generated successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(doc_generating: false, doc_gen_ref: nil)
         |> put_flash(:error, "Failed to save documentation")}
    end
  end

  @impl true
  def handle_info({ref, {:error, _reason}}, %{assigns: %{doc_gen_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(doc_generating: false, doc_gen_ref: nil)
     |> put_flash(:error, "Failed to generate documentation")}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{test_gen_ref: ref}} = socket
      ) do
    {:noreply, assign(socket, test_generating: false, test_gen_ref: nil)}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{test_run_ref: ref}} = socket
      ) do
    {:noreply, assign(socket, test_running: false, test_run_ref: nil)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{doc_gen_ref: ref}} = socket) do
    {:noreply, assign(socket, doc_generating: false, doc_gen_ref: nil)}
  end

  defp record_generation_usage(socket, operation, usage) do
    scope = socket.assigns.current_scope
    provider = Config.default_provider()

    LLM.record_usage(%{
      user_id: scope.user.id,
      organization_id: socket.assigns.org.id,
      provider: to_string(provider.name),
      model: provider.model,
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      cost_cents: 0,
      operation: operation,
      api_id: socket.assigns.api.id,
      duration_ms: 0
    })
  end

  defp lazy_load_tab(socket, "test") when not socket.assigns.history_loaded do
    history = Testing.list_test_requests(socket.assigns.api.id)
    assign(socket, test_history: history, history_loaded: true)
  end

  defp lazy_load_tab(socket, "auto_tests") when not socket.assigns.auto_test_suites_loaded do
    api_id = socket.assigns.api.id
    suites = Testing.list_test_suites(api_id)
    latest = Testing.get_latest_test_suite(api_id)

    code = if latest, do: latest.test_code, else: nil
    results = if latest && latest.results, do: latest.results, else: []

    parsed_results =
      Enum.map(results, fn r ->
        %{
          name: r["name"] || "",
          status: r["status"] || "error",
          duration_ms: r["duration_ms"] || 0,
          error: r["error"]
        }
      end)

    assign(socket,
      auto_test_suites: suites,
      auto_test_suites_loaded: true,
      auto_test_code: code,
      auto_test_results: parsed_results
    )
  end

  defp lazy_load_tab(socket, "keys") when not socket.assigns.keys_loaded do
    keys = Keys.list_keys(socket.assigns.api.id)
    assign(socket, api_keys: keys, keys_loaded: true)
  end

  defp lazy_load_tab(socket, "publish") do
    api_id = socket.assigns.api.id

    metrics = %{
      count_24h: Analytics.invocations_count(api_id, period: :day),
      success_rate: Analytics.success_rate(api_id, period: :day),
      avg_latency: Analytics.avg_latency(api_id, period: :day)
    }

    assign(socket, metrics: metrics)
  end

  defp lazy_load_tab(socket, _tab), do: socket

  defp push_editor_value(socket, code) do
    editor_path = "api_#{socket.assigns.api.id}.ex"
    LiveMonacoEditor.set_value(socket, code, to: editor_path)
  end

  defp resolve_organization(socket, params) do
    scope = socket.assigns.current_scope

    case params["org"] do
      nil ->
        scope.organization

      org_id ->
        org = Blackboex.Organizations.get_organization(org_id)

        if org && Blackboex.Organizations.get_user_membership(org, scope.user) do
          org
        else
          nil
        end
    end
  end

  defp build_request(assigns) do
    headers = build_header_list(assigns.test_headers)

    headers =
      if assigns.test_api_key != "" do
        headers ++ [{"x-api-key", assigns.test_api_key}]
      else
        headers
      end

    method = assigns.test_method |> String.downcase() |> String.to_existing_atom()

    body =
      if method in [:post, :put, :patch],
        do: assigns.test_body_json,
        else: nil

    %{method: method, url: assigns.test_url, headers: headers, body: body}
  end

  defp build_header_list(headers) do
    headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Enum.map(fn h -> {h.key, h.value} end)
  end

  defp headers_to_persist(assigns) do
    assigns.test_headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Map.new(fn h -> {h.key, h.value} end)
  end

  defp validate_response(response, api) do
    ResponseValidator.validate(response, api.param_schema)
  end

  defp update_item(items, id, field, value) do
    Enum.map(items, fn item ->
      if item.id == id, do: Map.put(item, field, value), else: item
    end)
  end

  defp default_test_body(api) do
    if api.example_request do
      Jason.encode!(api.example_request, pretty: true)
    else
      "{}"
    end
  end

  defp history_status_color(status) when status >= 200 and status < 300,
    do: "bg-green-50 text-green-700"

  defp history_status_color(status) when status >= 400 and status < 500,
    do: "bg-yellow-50 text-yellow-700"

  defp history_status_color(status) when status >= 500,
    do: "bg-red-50 text-red-700"

  defp history_status_color(_), do: "bg-muted text-muted-foreground"

  defp tab_label("info"), do: "Info"
  defp tab_label("versions"), do: "Versions"
  defp tab_label("test"), do: "Test"
  defp tab_label("auto_tests"), do: "Auto Tests"
  defp tab_label("keys"), do: "Keys"
  defp tab_label("publish"), do: "Publish"

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp auto_test_badge_color(results) do
    if Enum.all?(results, &(&1.status == "passed")) do
      "bg-green-100 text-green-700"
    else
      "bg-red-100 text-red-700"
    end
  end

  defp test_pass_count(results) do
    Enum.count(results, &(&1.status == "passed"))
  end

  defp suite_status_color("passed"), do: "bg-green-100 text-green-700"
  defp suite_status_color("failed"), do: "bg-red-100 text-red-700"
  defp suite_status_color("running"), do: "bg-blue-100 text-blue-700"
  defp suite_status_color(_), do: "bg-gray-100 text-gray-700"

  defp friendly_llm_error(:timeout), do: "A requisição demorou demais. Tente novamente."

  defp friendly_llm_error(:rate_limited),
    do: "Muitas requisições. Aguarde um momento e tente novamente."

  defp friendly_llm_error(:econnrefused),
    do: "Não foi possível conectar ao serviço de IA. Tente novamente mais tarde."

  defp friendly_llm_error(:too_many_messages),
    do: "Conversa muito longa. Use 'Nova conversa' para recomeçar."

  defp friendly_llm_error(reason) when is_binary(reason), do: "Erro: #{reason}"
  defp friendly_llm_error(reason), do: "Erro inesperado: #{inspect(reason)}"

  defp handle_llm_response(socket, conversation, response, instruction) do
    case EditPrompts.parse_response(response) do
      {:ok, proposed_code, explanation} ->
        # Persist assistant message
        {:ok, conversation} = Conversations.append_message(conversation, "assistant", explanation)

        diff = DiffEngine.compute_diff(socket.assigns.code, proposed_code)

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false,
           pending_edit: %{
             code: proposed_code,
             diff: diff,
             explanation: explanation,
             instruction: instruction
           }
         )}

      {:error, :no_code_found} ->
        {:ok, conversation} =
          Conversations.append_message(
            conversation,
            "assistant",
            response
          )

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false
         )}
    end
  end
end
