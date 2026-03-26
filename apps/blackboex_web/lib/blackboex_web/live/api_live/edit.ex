defmodule BlackboexWeb.ApiLive.Edit do
  @moduledoc """
  LiveView for editing API code with Monaco Editor, versioning, and compilation.
  Uses an IDE-like layout with toggleable right panel (Chat/Config) and bottom panel (Test/Versions).
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
  alias Blackboex.CodeGen.SchemaExtractor
  alias Blackboex.CodeGen.UnifiedPipeline
  alias Blackboex.Docs.DocGenerator
  alias Blackboex.LLM
  alias Blackboex.LLM.Config
  alias Blackboex.Testing
  alias Blackboex.Testing.RequestExecutor
  alias Blackboex.Testing.ResponseValidator
  alias Blackboex.Testing.SampleData
  alias Blackboex.Testing.SnippetGenerator

  import BlackboexWeb.Components.EditorToolbar
  import BlackboexWeb.Components.StatusBar
  import BlackboexWeb.Components.BottomPanel
  import BlackboexWeb.Components.RightPanel
  import BlackboexWeb.Components.CommandPalette
  import BlackboexWeb.Components.ValidationDashboard

  # ── Mount ──────────────────────────────────────────────────────────────

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
        versions = Apis.list_versions(api.id)
        {:ok, conversation} = Conversations.get_or_create_conversation(api.id)

        generating? =
          api.generation_status in ["pending", "generating", "validating"]

        if generating? do
          Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")
          Process.send_after(self(), :check_generation_status, 5_000)
        end

        {:ok,
         assign(socket,
           api: api,
           org: org,
           code: api.source_code || "",
           test_code: api.test_code || "",
           page_title: "Edit: #{api.name}",
           saving: false,
           versions: versions,
           selected_version: nil,
           diff_old: nil,
           diff_new: nil,
           # Chat assigns
           chat_messages: conversation.messages,
           chat_input: "",
           chat_loading: false,
           chat_conversation: conversation,
           pending_edit: nil,
           streaming_tokens: "",
           # Editor assigns
           editor_tab: "code",
           # Pipeline assigns
           pipeline_ref: nil,
           pipeline_status: nil,
           validation_report: nil,
           test_summary: nil,
           # Test assigns
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
           doc_generating: false,
           doc_gen_ref: nil,
           # Key/Publish assigns
           api_keys: [],
           keys_loaded: false,
           plain_key_flash: nil,
           metrics: nil,
           # Panel state
           right_panel: if(generating?, do: :chat, else: nil),
           bottom_panel_open: false,
           bottom_tab: "test",
           command_palette_open: false,
           command_palette_query: "",
           command_palette_selected: 0,
           # Generation state
           generation_status: api.generation_status,
           generation_tokens: ""
         )}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full" id="editor-root" phx-hook="KeyboardShortcuts">
      <%!-- Toolbar --%>
      <.editor_toolbar
        api={@api}
        code={@code}
        saving={@saving}
        right_panel={@right_panel}
        bottom_panel_open={@bottom_panel_open}
        selected_version={@selected_version}
        generation_status={@generation_status}
      />

      <%!-- Main area: editor + panels --%>
      <div class="flex flex-1 min-h-0">
        <%!-- Editor column (editor + bottom panel stacked vertically) --%>
        <div class="flex flex-col flex-1 min-w-0">
          <%!-- Editor Tab Bar --%>
          <div class="flex items-center border-b px-2 shrink-0 bg-card">
            <button
              :for={tab <- ~w(code tests)}
              phx-click="switch_editor_tab"
              phx-value-tab={tab}
              class={[
                "px-3 py-1.5 text-xs font-medium border-b-2 transition-colors",
                if(tab == @editor_tab,
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {editor_tab_label(tab)}
              <span
                :if={tab == "tests" && @test_summary}
                class={[
                  "ml-1 inline-flex rounded-full px-1.5 text-[10px] font-semibold",
                  test_summary_class(@test_summary)
                ]}
              >
                {@test_summary}
              </span>
            </button>
          </div>

          <%!-- Monaco Editor --%>
          <div
            id="monaco-container"
            phx-hook="MonacoStreaming"
            style="flex: 1 1 0%; min-height: 0; position: relative;"
          >
            <LiveMonacoEditor.code_editor
              path={"api_#{@api.id}.ex"}
              value={editor_value(@editor_tab, @code, @test_code)}
              change="editor_changed"
              style="position: absolute; top: 0; left: 0; right: 0; bottom: 0;"
              opts={
                Map.merge(LiveMonacoEditor.default_opts(), %{
                  "language" => "elixir",
                  "fontSize" => 14,
                  "minimap" => %{"enabled" => false},
                  "wordWrap" => "on",
                  "scrollBeyondLastLine" => false,
                  "automaticLayout" => true,
                  "scrollbar" => %{"alwaysConsumeMouseWheel" => true},
                  "readOnly" =>
                    @selected_version != nil or
                      @generation_status in ["pending", "generating", "validating"]
                })
              }
            />

          </div>

          <%!-- Bottom Panel --%>
          <.bottom_panel
            :if={@bottom_panel_open}
            active_tab={@bottom_tab}
            validation_report={@validation_report}
          >
            {render_bottom_content(assigns)}
          </.bottom_panel>
        </div>

        <%!-- Right Panel --%>
        <.right_panel :if={@right_panel} mode={@right_panel}>
          {render_right_content(assigns)}
        </.right_panel>
      </div>

      <%!-- Status Bar --%>
      <.status_bar api={@api} versions={@versions} selected_version={@selected_version} />

      <%!-- Command Palette (modal overlay) --%>
      <.command_palette
        open={@command_palette_open}
        query={@command_palette_query}
        api={@api}
        selected_index={@command_palette_selected}
      />
    </div>
    """
  end

  # ── Bottom Panel Content ───────────────────────────────────────────────

  defp render_bottom_content(%{bottom_tab: "test"} = assigns) do
    ~H"""
    <div class="flex gap-3 h-full">
      <%!-- Request Builder --%>
      <div class="flex-1 min-w-0 overflow-auto">
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
      </div>

      <%!-- Response Viewer --%>
      <div class="flex-1 min-w-0 overflow-auto">
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

      <%!-- Test History Sidebar --%>
      <div class="w-52 shrink-0 border-l pl-3 overflow-y-auto">
        <div class="flex items-center justify-between mb-2">
          <h4 class="text-xs font-semibold text-muted-foreground uppercase">History</h4>
          <button
            :if={@test_history != []}
            phx-click="clear_history"
            data-confirm="Limpar histórico de requests?"
            class="text-[10px] text-destructive hover:underline"
          >
            Limpar
          </button>
        </div>

        <div class="flex flex-wrap gap-1 mb-2">
          <button
            :for={lang <- ~w(curl python javascript elixir ruby go)}
            phx-click="copy_snippet"
            phx-value-language={lang}
            class="rounded border px-1.5 py-0.5 text-[10px] hover:bg-accent"
          >
            {lang}
          </button>
        </div>

        <%= if @test_history == [] do %>
          <p class="text-[10px] text-muted-foreground">No requests yet</p>
        <% else %>
          <div class="space-y-1">
            <div
              :for={item <- @test_history}
              phx-click="load_history_item"
              phx-value-id={item.id}
              class="rounded border p-1.5 text-[10px] cursor-pointer hover:bg-accent"
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-1">
                  <span class="font-semibold">{item.method}</span>
                  <span class="text-muted-foreground truncate max-w-[60px]">{item.path}</span>
                </div>
                <span class={[
                  "inline-flex rounded-full px-1 py-0 text-[9px] font-semibold",
                  history_status_color(item.response_status)
                ]}>
                  {item.response_status}
                </span>
              </div>
              <div class="text-muted-foreground mt-0.5">{item.duration_ms}ms</div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_bottom_content(%{bottom_tab: "validation"} = assigns) do
    ~H"""
    <.validation_dashboard
      report={@validation_report}
      loading={@pipeline_status != nil && @pipeline_status != :done}
    />
    """
  end

  defp render_bottom_content(%{bottom_tab: "versions"} = assigns) do
    ~H"""
    <div class="space-y-2">
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
            <div class="flex gap-2">
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

  # ── Right Panel Content ────────────────────────────────────────────────

  defp render_right_content(%{right_panel: :chat} = assigns) do
    ~H"""
    <.live_component
      module={BlackboexWeb.Components.ChatPanel}
      id="chat-panel"
      messages={@chat_messages}
      input={@chat_input}
      loading={@chat_loading or @generation_status in ["pending", "generating", "validating"]}
      api_id={@api.id}
      pending_edit={@pending_edit}
      template_type={@api.template_type}
      streaming_tokens={@streaming_tokens}
      pipeline_status={@pipeline_status || generation_to_pipeline_status(@generation_status)}
    />
    """
  end

  defp render_right_content(%{right_panel: :config} = assigns) do
    ~H"""
    <div class="p-4 space-y-4 overflow-y-auto h-full">
      {render_config_info(assigns)}
      {render_config_keys(assigns)}
      {render_config_publish(assigns)}
    </div>
    """
  end

  defp render_config_info(assigns) do
    ~H"""
    <details open>
      <summary class="text-xs font-semibold text-muted-foreground uppercase cursor-pointer py-2 select-none">
        Informações
      </summary>
      <div class="space-y-2 text-sm pb-4">
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
    </details>
    """
  end

  defp render_config_keys(assigns) do
    ~H"""
    <details>
      <summary class="text-xs font-semibold text-muted-foreground uppercase cursor-pointer py-2 select-none border-t pt-4">
        API Keys
      </summary>
      <div class="space-y-3 pb-4">
        <button
          phx-click="create_key"
          class="rounded bg-primary px-2 py-1 text-xs text-primary-foreground hover:bg-primary/90"
        >
          New Key
        </button>

        <%= if @plain_key_flash do %>
          <div class="rounded border-2 border-primary bg-muted p-2 text-xs space-y-1">
            <p class="font-semibold text-foreground">
              Copy this key now — it won't be shown again:
            </p>
            <code class="block bg-accent text-accent-foreground p-1.5 rounded font-mono text-xs break-all select-all">
              {@plain_key_flash}
            </code>
            <button
              phx-click="dismiss_key_flash"
              class="text-primary hover:underline text-[10px]"
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
                  if(key.revoked_at,
                    do: "bg-red-100 text-red-700",
                    else: "bg-green-100 text-green-700"
                  )
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
    </details>
    """
  end

  defp render_config_publish(assigns) do
    ~H"""
    <details>
      <summary class="text-xs font-semibold text-muted-foreground uppercase cursor-pointer py-2 select-none border-t pt-4">
        Publicação
      </summary>
      <div class="space-y-3 pb-4">
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
        <% end %>

        <%= if @api.status == "draft" do %>
          <p class="text-xs text-muted-foreground">
            Compile the API first before publishing.
          </p>
        <% end %>

        <%!-- Documentation & OpenAPI --%>
        <div class="border-t pt-3 mt-3">
          <h4 class="text-xs font-semibold text-muted-foreground uppercase mb-2">
            API Documentation
          </h4>

          <%!-- OpenAPI links — available for any compiled API --%>
          <%= if @api.status in ["compiled", "published"] do %>
            <div class="flex flex-col gap-1 mb-2">
              <a
                href={"/api/#{@org.slug}/#{@api.slug}/docs"}
                target="_blank"
                class="flex items-center gap-1.5 text-xs text-primary hover:underline"
              >
                <.icon name="hero-document-text" class="size-3.5" /> Swagger UI
              </a>
              <a
                href={"/api/#{@org.slug}/#{@api.slug}/openapi.json"}
                target="_blank"
                class="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground hover:underline"
              >
                <.icon name="hero-code-bracket" class="size-3.5" /> OpenAPI JSON
              </a>
            </div>
          <% end %>

          <%!-- Markdown docs generation --%>
          <%= if @api.status in ["compiled", "published"] do %>
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
          <% else %>
            <p class="text-xs text-muted-foreground">
              Save to compile the API and enable documentation.
            </p>
          <% end %>
        </div>
      </div>
    </details>
    """
  end

  # ── Panel Toggle Events ────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, toggle_right_panel(socket, :chat)}
  end

  @impl true
  def handle_event("toggle_config", _params, socket) do
    {:noreply, toggle_right_panel(socket, :config)}
  end

  @impl true
  def handle_event("toggle_bottom_panel", _params, socket) do
    new_open = !socket.assigns.bottom_panel_open
    socket = assign(socket, bottom_panel_open: new_open)

    socket =
      if new_open, do: lazy_load_bottom_tab(socket, socket.assigns.bottom_tab), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_command_palette", _params, socket) do
    {:noreply,
     assign(socket,
       command_palette_open: !socket.assigns.command_palette_open,
       command_palette_query: "",
       command_palette_selected: 0
     )}
  end

  @impl true
  def handle_event("close_panels", _params, socket) do
    cond do
      socket.assigns.command_palette_open ->
        {:noreply, assign(socket, command_palette_open: false, command_palette_query: "")}

      socket.assigns.right_panel != nil ->
        {:noreply, assign(socket, right_panel: nil)}

      socket.assigns.bottom_panel_open ->
        {:noreply, assign(socket, bottom_panel_open: false)}

      true ->
        {:noreply, socket}
    end
  end

  @valid_bottom_tabs ~w(test validation versions)

  @impl true
  def handle_event("switch_bottom_tab", %{"tab" => tab}, socket)
      when tab in @valid_bottom_tabs do
    socket =
      socket
      |> assign(bottom_tab: tab)
      |> lazy_load_bottom_tab(tab)

    {:noreply, socket}
  end

  # ── Command Palette Events ────────────────────────────────────────────

  @impl true
  def handle_event("command_palette_search", %{"command_query" => query}, socket) do
    {:noreply, assign(socket, command_palette_query: query, command_palette_selected: 0)}
  end

  @impl true
  def handle_event("command_palette_navigate", %{"direction" => "up"}, socket) do
    idx = max(socket.assigns.command_palette_selected - 1, 0)
    {:noreply, assign(socket, command_palette_selected: idx)}
  end

  def handle_event("command_palette_navigate", %{"direction" => "down"}, socket) do
    commands = filter_commands(socket.assigns.command_palette_query, socket.assigns.api)
    idx = min(socket.assigns.command_palette_selected + 1, length(commands) - 1)
    {:noreply, assign(socket, command_palette_selected: idx)}
  end

  @impl true
  def handle_event("command_palette_exec", %{"event" => event_name}, socket) do
    socket = assign(socket, command_palette_open: false, command_palette_query: "")
    execute_command(socket, event_name)
  end

  @impl true
  def handle_event("command_palette_exec_first", _params, socket) do
    commands =
      filter_commands(
        socket.assigns.command_palette_query,
        socket.assigns.api
      )

    case Enum.at(commands, socket.assigns.command_palette_selected) do
      nil ->
        {:noreply, socket}

      cmd ->
        socket =
          assign(socket,
            command_palette_open: false,
            command_palette_query: "",
            command_palette_selected: 0
          )

        execute_command(socket, cmd.event)
    end
  end

  # ── Code & Editor Events ──────────────────────────────────────────────

  @impl true
  def handle_event("switch_editor_tab", %{"tab" => tab}, socket) when tab in ~w(code tests) do
    value =
      case tab do
        "code" -> socket.assigns.code
        "tests" -> socket.assigns.test_code
      end

    {:noreply,
     socket
     |> assign(editor_tab: tab)
     |> push_editor_value(value)}
  end

  @impl true
  def handle_event("editor_changed", %{"value" => value}, socket) do
    case socket.assigns.editor_tab do
      "code" -> {:noreply, assign(socket, code: value)}
      "tests" -> {:noreply, assign(socket, test_code: value)}
    end
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{saving: true}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    do_save_and_validate(socket)
  end

  # ── Version Events ────────────────────────────────────────────────────

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
        code = new_version.code
        test_code = new_version.test_code || socket.assigns.test_code

        task = start_validation_pipeline(api, code, test_code)

        {:noreply,
         socket
         |> assign(
           api: api,
           code: code,
           test_code: test_code,
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           pipeline_ref: task.ref,
           pipeline_status: :formatting,
           bottom_panel_open: true,
           bottom_tab: "validation"
         )
         |> push_editor_value(code)
         |> put_flash(:info, "Rolled back to v#{number}")}

      {:error, :version_not_found} ->
        {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  # ── Publish Events ────────────────────────────────────────────────────

  @impl true
  def handle_event("publish", _params, socket) do
    %{api: api, org: org} = socket.assigns

    case Apis.publish(api, org) do
      {:ok, published_api, plain_key} ->
        {:noreply,
         socket
         |> assign(
           api: published_api,
           plain_key_flash: plain_key,
           right_panel: :config,
           api_keys: Keys.list_keys(published_api.id),
           keys_loaded: true
         )
         |> lazy_load_tab("publish")
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

  # ── Key Management Events ─────────────────────────────────────────────

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

  # ── Test Events ────────────────────────────────────────────────────────

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

  @max_test_items 50

  @impl true
  def handle_event("add_param", _params, socket) do
    if length(socket.assigns.test_params) >= @max_test_items do
      {:noreply, put_flash(socket, :error, "Maximum #{@max_test_items} parameters allowed")}
    else
      new_param = %{key: "", value: "", id: Ecto.UUID.generate()}
      {:noreply, assign(socket, test_params: socket.assigns.test_params ++ [new_param])}
    end
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
    if length(socket.assigns.test_headers) >= @max_test_items do
      {:noreply, put_flash(socket, :error, "Maximum #{@max_test_items} headers allowed")}
    else
      new_header = %{key: "", value: "", id: Ecto.UUID.generate()}
      {:noreply, assign(socket, test_headers: socket.assigns.test_headers ++ [new_header])}
    end
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
  def handle_event("send_request", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send_request", _params, socket) do
    request = build_request(socket.assigns)

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply,
     assign(socket,
       test_loading: true,
       test_error: nil,
       test_ref: task.ref,
       bottom_panel_open: true,
       bottom_tab: "test"
     )}
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

    # Auto-open bottom panel on test tab
    {:noreply,
     assign(socket,
       test_loading: true,
       test_error: nil,
       test_ref: task.ref,
       bottom_panel_open: true,
       bottom_tab: "test"
     )}
  end

  @impl true
  def handle_event("generate_sample", _params, socket) do
    sample = SampleData.generate(socket.assigns.api)
    body = Jason.encode!(sample.happy_path, pretty: true)

    {:noreply,
     assign(socket,
       test_body_json: body,
       test_body_error: nil,
       request_tab: "body",
       bottom_panel_open: true,
       bottom_tab: "test"
     )}
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

  # ── Chat Events ────────────────────────────────────────────────────────

  @impl true
  def handle_event("send_chat", %{"chat_input" => ""}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_chat", %{"chat_input" => message}, socket) do
    conversation = socket.assigns.chat_conversation

    case Conversations.append_message(conversation, "user", message) do
      {:ok, conversation} ->
        do_chat_request(socket, conversation, message)

      {:error, :too_many_messages} ->
        {:noreply,
         put_flash(socket, :error, "Conversa muito longa. Use 'Nova conversa' para recomeçar.")}

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

      %{code: proposed_code, test_code: proposed_test_code, instruction: instruction} ->
        do_accept_edit(socket, proposed_code, proposed_test_code, instruction)
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

  # ── Cancel Pipeline ──────────────────────────────────────────────────

  @impl true
  def handle_event("cancel_pipeline", _params, socket) do
    if ref = socket.assigns.pipeline_ref do
      Task.shutdown(ref, :brutal_kill)
    end

    {:noreply,
     assign(socket,
       pipeline_ref: nil,
       pipeline_status: nil,
       chat_loading: false,
       streaming_tokens: ""
     )}
  end

  # ── Doc Generation Events ─────────────────────────────────────────────

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

  # ── Task.async Result Handlers ────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, %{assigns: %{test_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        violations = validate_response(response, socket.assigns.api)
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

  # Streaming tokens from LLM
  @impl true
  def handle_info({:llm_token, token}, socket) do
    {:noreply, assign(socket, streaming_tokens: socket.assigns.streaming_tokens <> token)}
  end

  # Pipeline progress updates
  @impl true
  def handle_info({:pipeline_progress, progress}, socket) do
    {:noreply, assign(socket, pipeline_status: progress.step)}
  end

  # Pipeline task completed successfully
  @impl true
  def handle_info(
        {ref, {:ok, %{code: _, validation: _} = result}},
        %{assigns: %{pipeline_ref: ref}} = socket
      ) do
    Process.demonitor(ref, [:flush])
    handle_pipeline_result(socket, result)
  end

  # Pipeline task failed
  @impl true
  def handle_info(
        {ref, {:error, reason}},
        %{assigns: %{pipeline_ref: ref}} = socket
      )
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    handle_pipeline_error(socket, reason)
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

  # Pipeline task crashed
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{pipeline_ref: ref}} = socket
      ) do
    {:noreply,
     assign(socket,
       pipeline_ref: nil,
       pipeline_status: nil,
       chat_loading: false,
       streaming_tokens: ""
     )}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{doc_gen_ref: ref}} = socket) do
    {:noreply, assign(socket, doc_generating: false, doc_gen_ref: nil)}
  end

  # ── Generation PubSub handlers ─────────────────────────────────────────

  @impl true
  def handle_info(:check_generation_status, socket) do
    if socket.assigns.generation_status in ["pending", "generating", "validating"] do
      api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

      cond do
        is_nil(api) ->
          {:noreply, socket}

        api.generation_status == "completed" ->
          send(
            self(),
            {:generation_complete,
             %{
               code: api.source_code || "",
               test_code: api.test_code,
               validation: nil,
               template: api.template_type
             }}
          )

          {:noreply, socket}

        api.generation_status == "failed" ->
          send(self(), {:generation_failed, api.generation_error || "Generation failed"})
          {:noreply, socket}

        true ->
          Process.send_after(self(), :check_generation_status, 5_000)
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:generation_token, token}, socket) do
    {:noreply,
     socket
     |> assign(
       code: socket.assigns.code <> token,
       generation_tokens: socket.assigns.generation_tokens <> token,
       streaming_tokens: socket.assigns.streaming_tokens <> token
     )
     |> push_event("monaco:append_text", %{text: token})}
  end

  @impl true
  def handle_info({:generation_status, status}, socket) do
    {:noreply, assign(socket, generation_status: status)}
  end

  @impl true
  def handle_info({:generation_progress, progress}, socket) do
    {:noreply, assign(socket, pipeline_status: progress.step)}
  end

  @impl true
  def handle_info({:generation_complete, result}, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

    conversation = socket.assigns.chat_conversation

    # Only add user message if not already present (it's seeded in mount)
    has_user_msg = Enum.any?(conversation.messages, &(&1["role"] == "user"))

    conversation =
      if has_user_msg do
        conversation
      else
        case Conversations.append_message(conversation, "user", api.description || "Generate API") do
          {:ok, c} -> c
          _ -> conversation
        end
      end

    {:ok, conversation} =
      Conversations.append_message(conversation, "assistant", "Código gerado com sucesso.")

    {:noreply,
     socket
     |> assign(
       api: api,
       code: result.code,
       test_code: result.test_code || "",
       generation_status: "completed",
       generation_tokens: "",
       streaming_tokens: "",
       pipeline_status: nil,
       chat_loading: false,
       chat_messages: conversation.messages,
       chat_conversation: conversation,
       validation_report: result.validation,
       test_summary:
         if(result.validation, do: format_test_summary(result.validation.test_results), else: nil),
       versions: Apis.list_versions(api.id),
       bottom_panel_open: result.validation != nil,
       bottom_tab: "validation"
     )
     |> push_editor_value(result.code)
     |> put_flash(:info, "API generated successfully")}
  end

  @impl true
  def handle_info({:generation_failed, reason}, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

    conversation = socket.assigns.chat_conversation

    has_user_msg = Enum.any?(conversation.messages, &(&1["role"] == "user"))

    conversation =
      if has_user_msg do
        conversation
      else
        case Conversations.append_message(conversation, "user", api.description || "Generate API") do
          {:ok, c} -> c
          _ -> conversation
        end
      end

    {:ok, conversation} =
      Conversations.append_message(
        conversation,
        "assistant",
        "Generation failed: #{reason}. You can try again via chat."
      )

    {:noreply,
     socket
     |> assign(
       api: api || socket.assigns.api,
       generation_status: "failed",
       generation_tokens: "",
       streaming_tokens: "",
       pipeline_status: nil,
       chat_loading: false,
       chat_messages: conversation.messages,
       chat_conversation: conversation
     )
     |> put_flash(:error, "Code generation failed")}
  end

  # ── Private Helpers ────────────────────────────────────────────────────

  defp toggle_right_panel(socket, mode) do
    if socket.assigns.right_panel == mode do
      assign(socket, right_panel: nil)
    else
      socket
      |> assign(right_panel: mode)
      |> lazy_load_right_panel(mode)
    end
  end

  defp lazy_load_right_panel(socket, :config) do
    socket
    |> lazy_load_tab("keys")
    |> lazy_load_tab("publish")
  end

  defp lazy_load_right_panel(socket, _), do: socket

  defp lazy_load_bottom_tab(socket, "test"), do: lazy_load_tab(socket, "test")
  defp lazy_load_bottom_tab(socket, _), do: socket

  defp execute_command(socket, "quick_test_get") do
    handle_event("quick_test", %{"method" => "GET"}, socket)
  end

  defp execute_command(socket, "quick_test_post") do
    handle_event("quick_test", %{"method" => "POST"}, socket)
  end

  defp execute_command(socket, "copy_snippet_" <> lang) do
    handle_event("copy_snippet", %{"language" => lang}, socket)
  end

  defp execute_command(socket, event_name) do
    handle_event(event_name, %{}, socket)
  end

  defp do_accept_edit(socket, proposed_code, proposed_test_code, instruction) do
    scope = socket.assigns.current_scope

    case Apis.create_version(socket.assigns.api, %{
           code: proposed_code,
           test_code: proposed_test_code,
           source: "chat_edit",
           prompt: instruction,
           created_by_id: scope.user.id
         }) do
      {:ok, _version} ->
        api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

        maybe_register_compiled(
          api,
          socket.assigns.org,
          proposed_code,
          socket.assigns.pending_edit
        )

        {:noreply,
         socket
         |> assign(
           api: api,
           code: proposed_code,
           test_code: proposed_test_code || socket.assigns.test_code,
           versions: Apis.list_versions(api.id),
           pending_edit: nil,
           validation_report: socket.assigns.pending_edit[:validation]
         )
         |> push_editor_value(proposed_code)
         |> put_flash(:info, "Mudança aceita e versão criada")}

      {:error, changeset} ->
        Logger.error("Failed to create chat_edit version: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Falha ao criar versão")}
    end
  end

  defp maybe_register_compiled(api, org, code, %{validation: %{compilation: :pass}}) do
    case Compiler.compile(api, code) do
      {:ok, module} ->
        Registry.register(api.id, module, org_slug: org.slug, slug: api.slug)

        # Extract schema from compiled module and populate example_request/param_schema
        schema_attrs = extract_schema_attrs(module)
        Apis.update_api(api, Map.merge(%{status: "compiled"}, schema_attrs))

      _ ->
        :ok
    end
  end

  defp maybe_register_compiled(_api, _org, _code, _pending_edit), do: :ok

  defp extract_schema_attrs(module) do
    case SchemaExtractor.extract(module) do
      {:ok, schema} ->
        attrs = %{param_schema: SchemaExtractor.to_param_schema(schema)}

        attrs =
          if schema.request,
            do:
              Map.put(attrs, :example_request, SchemaExtractor.generate_example(schema.request)),
            else: attrs

        attrs =
          if schema.response,
            do:
              Map.put(attrs, :example_response, SchemaExtractor.generate_example(schema.response)),
            else: attrs

        attrs

      {:error, _} ->
        %{}
    end
  end

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
    api = socket.assigns.api
    code = socket.assigns.code
    lv_pid = self()

    socket =
      socket
      |> assign(
        chat_conversation: conversation,
        chat_messages: conversation.messages,
        chat_loading: true,
        chat_input: "",
        pipeline_status: :generating_code,
        streaming_tokens: ""
      )

    task =
      Task.async(fn ->
        UnifiedPipeline.run_for_edit(api, code, message, conversation.messages,
          progress_callback: fn progress -> send(lv_pid, {:pipeline_progress, progress}) end,
          token_callback: fn token -> send(lv_pid, {:llm_token, token}) end
        )
      end)

    {:noreply, assign(socket, pipeline_ref: task.ref)}
  end

  defp do_save_and_validate(socket) do
    api = socket.assigns.api
    code = socket.assigns.code
    test_code = socket.assigns.test_code
    has_changes = code != (api.source_code || "") or test_code != (api.test_code || "")

    if has_changes do
      save_and_run_pipeline(socket, api, code, test_code)
    else
      # No code changes — still run validation pipeline without creating a new version
      task = start_validation_pipeline(api, code, test_code)

      {:noreply,
       assign(socket,
         pipeline_ref: task.ref,
         pipeline_status: :formatting,
         bottom_panel_open: true,
         bottom_tab: "validation"
       )}
    end
  end

  defp save_and_run_pipeline(socket, api, code, test_code) do
    scope = socket.assigns.current_scope

    case Apis.create_version(api, %{
           code: code,
           test_code: test_code,
           source: "manual_edit",
           created_by_id: scope.user.id
         }) do
      {:ok, _version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)
        task = start_validation_pipeline(api, code, test_code)

        {:noreply,
         socket
         |> assign(
           api: api,
           saving: false,
           versions: Apis.list_versions(api.id),
           pipeline_ref: task.ref,
           pipeline_status: :formatting,
           bottom_panel_open: true,
           bottom_tab: "validation"
         )
         |> put_flash(:info, "Saved")}

      {:error, changeset} ->
        Logger.error("Failed to save version: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  @template_type_atoms %{
    "computation" => :computation,
    "crud" => :crud,
    "webhook" => :webhook
  }

  defp start_validation_pipeline(api, code, test_code) do
    lv_pid = self()
    template = Map.fetch!(@template_type_atoms, api.template_type)

    Task.async(fn ->
      UnifiedPipeline.validate_on_save(code, test_code, template,
        progress_callback: fn p -> send(lv_pid, {:pipeline_progress, p}) end
      )
    end)
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

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp history_status_color(status) when status >= 200 and status < 300,
    do: "bg-green-50 text-green-700"

  defp history_status_color(status) when status >= 400 and status < 500,
    do: "bg-yellow-50 text-yellow-700"

  defp history_status_color(status) when status >= 500,
    do: "bg-red-50 text-red-700"

  defp history_status_color(_), do: "bg-muted text-muted-foreground"

  defp handle_pipeline_result(socket, %{explanation: explanation} = result)
       when is_binary(explanation) do
    handle_chat_pipeline_result(socket, result)
  end

  defp handle_pipeline_result(socket, result) do
    handle_save_pipeline_result(socket, result)
  end

  defp handle_chat_pipeline_result(socket, result) do
    conversation = socket.assigns.chat_conversation
    code_diff = DiffEngine.compute_diff(socket.assigns.code, result.code)
    test_diff = compute_test_diff(socket.assigns.test_code, result.test_code)

    {:ok, conversation} =
      Conversations.append_message(conversation, "assistant", result.explanation)

    test_summary = format_test_summary(result.validation.test_results)

    {:noreply,
     socket
     |> assign(
       chat_conversation: conversation,
       chat_messages: conversation.messages,
       chat_loading: false,
       pipeline_ref: nil,
       pipeline_status: nil,
       streaming_tokens: "",
       test_summary: test_summary,
       pending_edit: %{
         code: result.code,
         test_code: result.test_code,
         diff: code_diff,
         test_diff: test_diff,
         explanation: result.explanation,
         instruction: "",
         validation: result.validation
       }
     )}
  end

  defp handle_save_pipeline_result(socket, result) do
    test_summary = format_test_summary(result.validation.test_results)

    maybe_register_compiled(
      socket.assigns.api,
      socket.assigns.org,
      result.code,
      %{validation: result.validation}
    )

    # Reload API to get updated example_request/param_schema from schema extraction
    updated_api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

    {:noreply,
     socket
     |> assign(
       code: result.code,
       validation_report: result.validation,
       test_summary: test_summary,
       pipeline_ref: nil,
       pipeline_status: nil,
       streaming_tokens: "",
       api: updated_api,
       test_body_json: default_test_body(updated_api)
     )}
  end

  defp compute_test_diff(_current, nil), do: []
  defp compute_test_diff(current, proposed), do: DiffEngine.compute_diff(current || "", proposed)

  defp handle_pipeline_error(socket, reason) do
    Logger.warning("Pipeline failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(
       chat_loading: false,
       pipeline_ref: nil,
       pipeline_status: nil,
       streaming_tokens: ""
     )
     |> put_flash(:error, "Pipeline failed: #{inspect(reason)}")}
  end

  defp format_test_summary(test_results) when is_list(test_results) and test_results != [] do
    passed = Enum.count(test_results, &(&1.status == "passed"))
    total = length(test_results)
    "#{passed}/#{total}"
  end

  defp format_test_summary(_), do: nil

  # ── Editor Tab Helpers ──────────────────────────────────────────────

  defp editor_tab_label("code"), do: "Code"
  defp editor_tab_label("tests"), do: "Tests"

  defp editor_value("code", code, _test_code), do: code
  defp editor_value("tests", _code, test_code), do: test_code

  defp generation_to_pipeline_status("pending"), do: :generating_code
  defp generation_to_pipeline_status("generating"), do: :generating_code
  defp generation_to_pipeline_status("validating"), do: :formatting
  defp generation_to_pipeline_status(_), do: nil

  defp test_summary_class(summary) do
    if String.contains?(summary, "/") do
      [passed, total] = String.split(summary, "/")
      if passed == total, do: "bg-green-100 text-green-700", else: "bg-red-100 text-red-700"
    else
      "bg-gray-100 text-gray-600"
    end
  end
end
