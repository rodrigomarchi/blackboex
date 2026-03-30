defmodule BlackboexWeb.ApiLive.Edit do
  @moduledoc """
  LiveView for editing API code with Monaco Editor, versioning, and compilation.
  Uses an IDE-like layout with toggleable right panel (Chat/Config) and bottom panel (Test/Versions).
  """

  use BlackboexWeb, :live_view

  require Logger

  import Ecto.Query

  alias Blackboex.Apis
  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Apis.Keys
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Billing.Enforcement
  alias Blackboex.Conversations, as: AgentConversations
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

        # Agent pipeline: check for active run on reconnection
        {agent_conversation, active_run_id} =
          resolve_agent_state(api.id)

        # Subscribe to API topic for agent_run_started
        Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")

        # Load full conversation events for chat timeline
        {agent_events, current_run} =
          load_conversation_events(agent_conversation)

        {:ok,
         assign(socket,
           api: api,
           org: org,
           code: api.source_code || "",
           test_code: api.test_code || "",
           page_title: "Edit: #{api.name}",
           versions: versions,
           selected_version: nil,
           diff_old: nil,
           diff_new: nil,
           # Chat assigns
           chat_input: "",
           chat_loading: active_run_id != nil,
           pending_edit: nil,
           streaming_tokens: "",
           # Tab state
           active_tab: if(active_run_id, do: "chat", else: "code"),
           # Pipeline assigns
           pipeline_status: nil,
           validation_report: restore_validation_report(api.validation_report),
           test_summary: derive_test_summary(api.validation_report),
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
           # Metrics assigns
           metrics_period: "7d",
           metrics_loaded: false,
           invocation_data: [],
           latency_data: [],
           error_data: [],
           total_invocations: 0,
           total_errors: 0,
           error_rate: 0.0,
           avg_latency: 0,
           # Key/Publish assigns
           api_keys: [],
           keys_loaded: false,
           plain_key_flash: nil,
           metrics: nil,
           command_palette_open: false,
           command_palette_query: "",
           command_palette_selected: 0,
           # Edit rollback state
           pre_edit_code: nil,
           # Generation state
           generation_status: api.generation_status,
           # Agent pipeline assigns
           current_run_id: active_run_id,
           current_run: current_run,
           agent_events: agent_events,
           agent_conversation: agent_conversation
         )}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @tabs [
    %{id: "chat", label: "Chat"},
    %{id: "code", label: "Code"},
    %{id: "tests", label: "Tests"},
    %{id: "validation", label: "Validation"},
    %{id: "docs", label: "Docs"},
    %{id: "versions", label: "Versions"},
    %{id: "run", label: "Run"},
    %{id: "metrics", label: "Metrics"},
    %{id: "keys", label: "API Keys"},
    %{id: "publish", label: "Publish"},
    %{id: "info", label: "Info"}
  ]

  @metric_periods %{"24h" => 1, "7d" => 7, "30d" => 30}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="flex flex-col h-full" id="editor-root" phx-hook="KeyboardShortcuts">
      <%!-- Toolbar --%>
      <.editor_toolbar
        api={@api}
        selected_version={@selected_version}
        generation_status={@generation_status}
      />

      <%!-- Main area: tabs + chat sidebar --%>
      <div class="flex flex-1 min-h-0">
        <%!-- Tab content column --%>
        <div class="flex flex-col flex-1 min-w-0">
          <%!-- Tab Bar --%>
          <div class="flex items-center border-b px-2 shrink-0 bg-card">
            <button
              :for={tab <- @tabs}
              phx-click="switch_tab"
              phx-value-tab={tab.id}
              class={[
                "px-3 py-1.5 text-xs font-medium border-b-2 transition-colors",
                if(tab.id == @active_tab,
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {tab.label}
              <span
                :if={tab.id == "tests" && @test_summary}
                class={[
                  "ml-1 inline-flex rounded-full px-1.5 text-[10px] font-semibold",
                  test_summary_class(@test_summary)
                ]}
              >
                {@test_summary}
              </span>
              <span
                :if={tab.id == "validation" && @validation_report}
                class={[
                  "ml-1 inline-flex rounded-full px-1.5 text-[10px] font-semibold",
                  if(@validation_report.overall == :pass,
                    do: "bg-green-100 text-green-700",
                    else: "bg-red-100 text-red-700"
                  )
                ]}
              >
                {if @validation_report.overall == :pass, do: "✓", else: "!"}
              </span>
            </button>
          </div>

          <%!-- Content Area --%>
          <div class="flex-1 min-h-0 relative overflow-hidden">
            {render_tab_content(assigns)}
          </div>
        </div>
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

  # ── Tab Content ───────────────────────────────────────────────────────

  defp render_tab_content(%{active_tab: "chat"} = assigns) do
    ~H"""
    <.live_component
      module={BlackboexWeb.Components.ChatPanel}
      id="chat-panel"
      events={@agent_events}
      input={@chat_input}
      loading={@chat_loading or @generation_status in ["pending", "generating", "validating"]}
      api_id={@api.id}
      pending_edit={@pending_edit}
      template_type={@api.template_type}
      streaming_tokens={if(@chat_loading, do: @streaming_tokens, else: "")}
      run={@current_run}
      pipeline_status={@pipeline_status}
    />
    """
  end

  defp render_tab_content(%{active_tab: tab} = assigns) when tab in ["code", "tests"] do
    ~H"""
    <div
      id="monaco-container"
      style="position: absolute; top: 0; left: 0; right: 0; bottom: 0;"
    >
      <LiveMonacoEditor.code_editor
        path={"api_#{@api.id}.ex"}
        value={editor_value(@active_tab, @code, @test_code)}
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
    """
  end

  defp render_tab_content(%{active_tab: "validation"} = assigns) do
    ~H"""
    <div class="p-4 overflow-y-auto h-full">
      <.validation_dashboard
        report={@validation_report}
        loading={@pipeline_status != nil && @pipeline_status != :done}
      />
    </div>
    """
  end

  defp render_tab_content(%{active_tab: "docs"} = assigns) do
    assigns = assign(assigns, :doc_content, assigns.api.documentation_md)

    ~H"""
    <div class="p-6 overflow-y-auto h-full">
      <%= if @doc_content && @doc_content != "" do %>
        <div class="prose prose-sm dark:prose-invert max-w-none">
          {raw(render_markdown(@doc_content))}
        </div>
      <% else %>
        <div class="flex flex-col items-center justify-center py-16 text-center">
          <.icon name="hero-document-text" class="size-10 text-muted-foreground mb-4" />
          <p class="text-sm font-medium">No documentation yet</p>
          <p class="text-xs text-muted-foreground mt-1">
            Documentation is generated automatically after code generation completes.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tab_content(%{active_tab: "versions"} = assigns) do
    ~H"""
    <div class="p-4 overflow-y-auto h-full space-y-2">
      <%= if @versions == [] do %>
        <p class="text-sm text-muted-foreground">
          No versions yet. Save to create the first version.
        </p>
      <% else %>
        <%= for version <- @versions do %>
          <div class={[
            "rounded border p-3 text-xs space-y-1",
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

  defp render_tab_content(%{active_tab: "run"} = assigns) do
    ~H"""
    <div class="flex gap-4 h-full p-4 overflow-hidden">
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

      <%!-- Test History --%>
      <div class="w-52 shrink-0 border-l pl-3 overflow-y-auto">
        <div class="flex items-center justify-between mb-2">
          <h4 class="text-xs font-semibold text-muted-foreground uppercase">History</h4>
          <button
            :if={@test_history != []}
            phx-click="clear_history"
            data-confirm="Clear request history?"
            class="text-[10px] text-destructive hover:underline"
          >
            Clear
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
                  <span class="text-muted-foreground truncate max-w-[80px]">{item.path}</span>
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

  # ── API Keys Tab ──────────────────────────────────────────────────────

  # ── Metrics Tab ──────────────────────────────────────────────────────

  defp render_tab_content(%{active_tab: "metrics"} = assigns) do
    ~H"""
    <div class="p-6 overflow-y-auto h-full space-y-6">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-semibold">Metrics</h2>
        <div class="flex gap-1">
          <button
            :for={period <- ["24h", "7d", "30d"]}
            phx-click="change_metrics_period"
            phx-value-period={period}
            class={[
              "px-3 py-1 rounded-md text-xs font-medium",
              if(@metrics_period == period,
                do: "bg-primary text-primary-foreground",
                else: "bg-muted text-muted-foreground hover:bg-accent"
              )
            ]}
          >
            {period}
          </button>
        </div>
      </div>

      <%!-- Stat Cards --%>
      <div class="grid grid-cols-4 gap-4">
        <div class="rounded-lg border p-4">
          <p class="text-xs text-muted-foreground">Invocations</p>
          <p class="text-2xl font-bold">{@total_invocations}</p>
        </div>
        <div class="rounded-lg border p-4">
          <p class="text-xs text-muted-foreground">Errors</p>
          <p class="text-2xl font-bold">{@total_errors}</p>
        </div>
        <div class="rounded-lg border p-4">
          <p class="text-xs text-muted-foreground">Error Rate</p>
          <p class="text-2xl font-bold">{@error_rate}%</p>
        </div>
        <div class="rounded-lg border p-4">
          <p class="text-xs text-muted-foreground">Avg Latency</p>
          <p class="text-2xl font-bold">{@avg_latency}ms</p>
        </div>
      </div>

      <%= if @invocation_data == [] do %>
        <div class="rounded-lg border border-dashed p-8 text-center">
          <.icon name="hero-chart-bar" class="size-10 mx-auto text-muted-foreground mb-3" />
          <p class="text-sm font-medium">No metrics data yet</p>
          <p class="text-xs text-muted-foreground mt-1">
            Publish and call your API to see stats. Data is aggregated hourly.
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-2 gap-4">
          <div class="rounded-lg border p-4">
            <BlackboexWeb.Components.Charts.bar_chart
              data={@invocation_data}
              title="Invocations"
            />
          </div>
          <div class="rounded-lg border p-4">
            <BlackboexWeb.Components.Charts.line_chart
              data={@latency_data}
              title="P95 Latency (ms)"
              color="#f59e0b"
            />
          </div>
        </div>
        <div class="rounded-lg border p-4">
          <BlackboexWeb.Components.Charts.bar_chart
            data={@error_data}
            title="Errors"
            color="#ef4444"
          />
        </div>
      <% end %>
    </div>
    """
  end

  # ── API Keys Tab ──────────────────────────────────────────────────────

  defp render_tab_content(%{active_tab: "keys"} = assigns) do
    ~H"""
    <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-semibold">API Keys</h2>
        <button
          phx-click="create_key"
          class="inline-flex items-center rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="size-3 mr-1" /> Create Key
        </button>
      </div>

      <%= if @plain_key_flash do %>
        <div class="rounded-lg border-2 border-amber-500 bg-amber-50 dark:bg-amber-950 p-4 space-y-2">
          <p class="text-sm font-semibold text-amber-800 dark:text-amber-200">
            Copy this key now — it won't be shown again
          </p>
          <div class="flex items-center gap-2">
            <code class="flex-1 rounded bg-background p-2 font-mono text-xs break-all select-all border">
              {@plain_key_flash}
            </code>
            <button
              phx-click="copy_key"
              class="shrink-0 rounded border px-2 py-1 text-xs hover:bg-accent"
            >
              Copy
            </button>
          </div>
          <button
            phx-click="dismiss_key_flash"
            class="text-xs text-muted-foreground hover:underline"
          >
            Dismiss
          </button>
        </div>
      <% end %>

      <%= if @api_keys == [] do %>
        <div class="rounded-lg border border-dashed p-8 text-center">
          <.icon name="hero-key" class="size-8 mx-auto text-muted-foreground mb-3" />
          <p class="text-sm font-medium">No API keys yet</p>
          <p class="text-xs text-muted-foreground mt-1">
            Keys are required to call published APIs. Create one to get started.
          </p>
        </div>
      <% else %>
        <div class="space-y-3">
          <div :for={key <- @api_keys} class="rounded-lg border p-4 space-y-3">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <code class="font-mono text-sm">{key.key_prefix}...</code>
                <span class={[
                  "inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold",
                  if(key.revoked_at,
                    do: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",
                    else: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
                  )
                ]}>
                  {if key.revoked_at, do: "Revoked", else: "Active"}
                </span>
                <span :if={key.label} class="text-xs text-muted-foreground">{key.label}</span>
              </div>
              <div :if={!key.revoked_at} class="flex items-center gap-2">
                <button
                  phx-click="rotate_key"
                  phx-value-key-id={key.id}
                  data-confirm="Rotate this key? The old key will be revoked immediately."
                  class="rounded border px-2 py-1 text-xs hover:bg-accent"
                >
                  Rotate
                </button>
                <button
                  phx-click="revoke_key"
                  phx-value-key-id={key.id}
                  data-confirm="Revoke this key? This cannot be undone."
                  class="rounded border border-destructive/50 px-2 py-1 text-xs text-destructive hover:bg-destructive/10"
                >
                  Revoke
                </button>
              </div>
            </div>

            <div class="grid grid-cols-3 gap-4 text-xs text-muted-foreground">
              <div>
                <span class="block text-[10px] uppercase tracking-wide">Created</span>
                {Calendar.strftime(key.inserted_at, "%Y-%m-%d")}
              </div>
              <div>
                <span class="block text-[10px] uppercase tracking-wide">Last used</span>
                {if key.last_used_at, do: time_ago(key.last_used_at), else: "never"}
              </div>
              <div>
                <span class="block text-[10px] uppercase tracking-wide">
                  {if key.revoked_at, do: "Revoked", else: "Expires"}
                </span>
                {cond do
                  key.revoked_at -> Calendar.strftime(key.revoked_at, "%Y-%m-%d")
                  key.expires_at -> Calendar.strftime(key.expires_at, "%Y-%m-%d")
                  true -> "never"
                end}
              </div>
            </div>

            <%= if !key.revoked_at && key.metrics do %>
              <div class="grid grid-cols-4 gap-2">
                <div class="rounded border p-2 text-center">
                  <p class="text-sm font-bold">{key.metrics.total_requests}</p>
                  <p class="text-[10px] text-muted-foreground">Requests</p>
                </div>
                <div class="rounded border p-2 text-center">
                  <p class="text-sm font-bold">{key.metrics.success_rate}%</p>
                  <p class="text-[10px] text-muted-foreground">Success</p>
                </div>
                <div class="rounded border p-2 text-center">
                  <p class="text-sm font-bold">{key.metrics.avg_latency}ms</p>
                  <p class="text-[10px] text-muted-foreground">Latency</p>
                </div>
                <div class="rounded border p-2 text-center">
                  <p class="text-sm font-bold">{key.metrics.errors}</p>
                  <p class="text-[10px] text-muted-foreground">Errors</p>
                </div>
              </div>
              <p class="text-[10px] text-muted-foreground">Last 7 days</p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Publish Tab ─────────────────────────────────────────────────────

  defp render_tab_content(%{active_tab: "publish"} = assigns) do
    ~H"""
    <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-6">
      <h2 class="text-sm font-semibold">Publication</h2>

      <%!-- Status card --%>
      <div class="rounded-lg border p-4 space-y-2">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="text-xs text-muted-foreground">Status</span>
            <span class={[
              "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
              status_color(@api.status)
            ]}>
              {@api.status}
            </span>
          </div>
          <%= if @api.status == "compiled" do %>
            <button
              phx-click="publish"
              class="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700"
            >
              Publish API
            </button>
          <% end %>
          <%= if @api.status == "published" do %>
            <button
              phx-click="unpublish"
              data-confirm="Unpublish this API? It will no longer be accessible."
              class="rounded-md border border-destructive px-3 py-1.5 text-xs font-medium text-destructive hover:bg-destructive/10"
            >
              Unpublish
            </button>
          <% end %>
        </div>
        <div class="flex items-center gap-2 text-xs">
          <span class="text-muted-foreground">URL</span>
          <code class="font-mono">/api/{@org.slug}/{@api.slug}</code>
          <button
            phx-click="copy_url"
            class="text-primary hover:underline text-[10px]"
          >
            Copy
          </button>
          <%= if @api.status == "draft" do %>
            <span class="text-muted-foreground">(preview)</span>
          <% end %>
        </div>
      </div>

      <%= if @api.status == "draft" do %>
        <p class="text-sm text-muted-foreground">
          Save the API to compile it. Once compiled, you can publish.
        </p>
      <% end %>

      <%= if @api.status == "compiled" do %>
        <p class="text-sm text-muted-foreground">
          Ready to publish. A default API key will be created automatically.
        </p>
      <% end %>

      <%!-- Metrics --%>
      <%= if @api.status == "published" && @metrics do %>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Metrics (24h)</h3>
          <div class="grid grid-cols-4 gap-3">
            <div class="rounded-lg border p-3 text-center">
              <p class="text-xl font-bold">{@metrics.count_24h}</p>
              <p class="text-[10px] text-muted-foreground">Total Calls</p>
            </div>
            <div class="rounded-lg border p-3 text-center">
              <p class="text-xl font-bold">{@metrics.success_rate}%</p>
              <p class="text-[10px] text-muted-foreground">Success Rate</p>
            </div>
            <div class="rounded-lg border p-3 text-center">
              <p class="text-xl font-bold">{@metrics.avg_latency}ms</p>
              <p class="text-[10px] text-muted-foreground">Avg Latency</p>
            </div>
            <div class="rounded-lg border p-3 text-center">
              <p class="text-xl font-bold">{@metrics[:error_count] || 0}</p>
              <p class="text-[10px] text-muted-foreground">Errors</p>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Documentation --%>
      <%= if @api.status in ["compiled", "published"] do %>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Documentation</h3>
          <div class="space-y-2">
            <div class="flex items-center justify-between rounded border p-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-document-text" class="size-4 text-muted-foreground" />
                <span class="text-sm">Swagger UI</span>
              </div>
              <a
                href={"/api/#{@org.slug}/#{@api.slug}/docs"}
                target="_blank"
                class="text-xs text-primary hover:underline"
              >
                Open
              </a>
            </div>
            <div class="flex items-center justify-between rounded border p-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-code-bracket" class="size-4 text-muted-foreground" />
                <span class="text-sm">OpenAPI JSON</span>
              </div>
              <a
                href={"/api/#{@org.slug}/#{@api.slug}/openapi.json"}
                target="_blank"
                class="text-xs text-primary hover:underline"
              >
                Open
              </a>
            </div>
            <div class="flex items-center justify-between rounded border p-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-document-check" class="size-4 text-muted-foreground" />
                <span class="text-sm">Markdown Docs</span>
                <%= if @api.documentation_md do %>
                  <span class="text-[10px] text-green-600 font-medium">Auto-generated</span>
                <% else %>
                  <span class="text-[10px] text-muted-foreground">Generated on save</span>
                <% end %>
              </div>
              <.link
                :if={@api.documentation_md}
                phx-click="switch_tab"
                phx-value-tab="docs"
                class="text-xs text-primary hover:underline"
              >
                View
              </.link>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Settings --%>
      <div>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Settings</h3>
        <form phx-submit="save_publish_settings" class="space-y-3">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="text-xs font-medium">HTTP Method</label>
              <select
                name="method"
                class="mt-1 w-full rounded-md border bg-background px-3 py-1.5 text-sm"
              >
                <option
                  :for={m <- ~w(GET POST PUT PATCH DELETE)}
                  value={m}
                  selected={m == @api.method}
                >
                  {m}
                </option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium">Visibility</label>
              <select
                name="visibility"
                class="mt-1 w-full rounded-md border bg-background px-3 py-1.5 text-sm"
              >
                <option value="private" selected={@api.visibility == "private"}>Private</option>
                <option value="public" selected={@api.visibility == "public"}>Public</option>
              </select>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              id="requires_auth"
              name="requires_auth"
              value="true"
              checked={@api.requires_auth}
              class="rounded border"
            />
            <label for="requires_auth" class="text-xs font-medium">
              Require authentication (API key)
            </label>
          </div>
          <button
            type="submit"
            class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
          >
            Save Settings
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Info Tab ────────────────────────────────────────────────────────

  defp render_tab_content(%{active_tab: "info"} = assigns) do
    ~H"""
    <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-6">
      <h2 class="text-sm font-semibold">API Information</h2>

      <%!-- General --%>
      <div>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">General</h3>
        <form phx-submit="update_info" class="space-y-3">
          <div>
            <label class="text-xs font-medium">Name</label>
            <input
              type="text"
              name="name"
              value={@api.name}
              maxlength="200"
              class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label class="text-xs font-medium">Description</label>
            <textarea
              name="description"
              rows="3"
              maxlength="10000"
              class="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
            >{@api.description}</textarea>
          </div>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span class="text-xs text-muted-foreground">Slug</span>
              <p class="font-mono">{@api.slug}</p>
            </div>
            <div>
              <span class="text-xs text-muted-foreground">Template</span>
              <p>{@api.template_type}</p>
            </div>
            <div>
              <span class="text-xs text-muted-foreground">Created</span>
              <p>{Calendar.strftime(@api.inserted_at, "%Y-%m-%d %H:%M")}</p>
            </div>
            <div>
              <span class="text-xs text-muted-foreground">Last modified</span>
              <p>{Calendar.strftime(@api.updated_at, "%Y-%m-%d %H:%M")}</p>
            </div>
          </div>
          <button
            type="submit"
            class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
          >
            Save Changes
          </button>
        </form>
      </div>

      <%!-- Code Stats --%>
      <div>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Code Stats</h3>
        <div class="grid grid-cols-4 gap-3">
          <div class="rounded-lg border p-3 text-center">
            <p class="text-xl font-bold">{count_lines(@api.source_code)}</p>
            <p class="text-[10px] text-muted-foreground">Source Lines</p>
          </div>
          <div class="rounded-lg border p-3 text-center">
            <p class="text-xl font-bold">{count_lines(@api.test_code)}</p>
            <p class="text-[10px] text-muted-foreground">Test Lines</p>
          </div>
          <div class="rounded-lg border p-3 text-center">
            <p class="text-xl font-bold">{length(@versions)}</p>
            <p class="text-[10px] text-muted-foreground">Versions</p>
          </div>
          <div class="rounded-lg border p-3 text-center">
            <p class="text-xl font-bold">
              {if @versions != [], do: "v#{hd(@versions).version_number}", else: "-"}
            </p>
            <p class="text-[10px] text-muted-foreground">Latest</p>
          </div>
        </div>
      </div>

      <%!-- Request/Response Schema --%>
      <%= if @api.param_schema || @api.example_request || @api.example_response do %>
        <div>
          <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">
            Request/Response Schema
          </h3>
          <div class="space-y-3">
            <%= if @api.param_schema do %>
              <div>
                <span class="text-xs font-medium">Param Schema</span>
                <pre class="mt-1 rounded-md bg-muted p-3 text-xs font-mono overflow-x-auto"><code>{format_json(@api.param_schema)}</code></pre>
              </div>
            <% end %>
            <div class="grid grid-cols-2 gap-3">
              <%= if @api.example_request do %>
                <div>
                  <span class="text-xs font-medium">Example Request</span>
                  <pre class="mt-1 rounded-md bg-muted p-3 text-xs font-mono overflow-x-auto"><code>{format_json(@api.example_request)}</code></pre>
                </div>
              <% end %>
              <%= if @api.example_response do %>
                <div>
                  <span class="text-xs font-medium">Example Response</span>
                  <pre class="mt-1 rounded-md bg-muted p-3 text-xs font-mono overflow-x-auto"><code>{format_json(@api.example_response)}</code></pre>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Danger Zone --%>
      <div>
        <h3 class="text-xs font-semibold text-muted-foreground uppercase mb-3">Danger Zone</h3>
        <div class="rounded-lg border border-destructive/30 p-4 flex items-center justify-between">
          <div>
            <p class="text-sm font-medium">Archive this API</p>
            <p class="text-xs text-muted-foreground">
              Removes from active list. Published APIs will be unpublished first.
            </p>
          </div>
          <button
            phx-click="archive_api"
            data-confirm="Archive this API? Published APIs will be unpublished. This cannot be undone."
            class="rounded-md border border-destructive px-3 py-1.5 text-xs font-medium text-destructive hover:bg-destructive/10"
          >
            Archive API
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── Tab Events ────────────────────────────────────────────────────────

  @valid_tabs ~w(chat code tests validation docs versions run metrics keys publish info)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    socket =
      socket
      |> assign(active_tab: tab)
      |> lazy_load_tab(tab)

    # When switching to code/tests, push the value to Monaco
    socket =
      case tab do
        "code" -> push_editor_value(socket, socket.assigns.code)
        "tests" -> push_editor_value(socket, socket.assigns.test_code)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, active_tab: "chat")}
  end

  # Keep old events as aliases for compatibility (command palette, keyboard shortcuts)
  @impl true
  def handle_event("toggle_config", _params, socket) do
    {:noreply, socket |> assign(active_tab: "publish") |> lazy_load_tab("publish")}
  end

  @impl true
  def handle_event("toggle_bottom_panel", _params, socket) do
    {:noreply, assign(socket, active_tab: "run")}
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
    if socket.assigns.command_palette_open do
      {:noreply, assign(socket, command_palette_open: false, command_palette_query: "")}
    else
      {:noreply, socket}
    end
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
    handle_event("switch_tab", %{"tab" => tab}, socket)
  end

  @impl true
  def handle_event("editor_changed", %{"value" => value}, socket) do
    case socket.assigns.active_tab do
      "code" -> {:noreply, assign(socket, code: value)}
      "tests" -> {:noreply, assign(socket, test_code: value)}
      _ -> {:noreply, socket}
    end
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

        {:noreply,
         socket
         |> assign(
           api: api,
           code: code,
           test_code: test_code,
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           validation_report: restore_validation_report(api.validation_report),
           test_summary: derive_test_summary(api.validation_report)
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
      {:ok, published_api} ->
        {:noreply,
         socket
         |> assign(api: published_api)
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
        keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
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
          keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
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
          keys = enrich_keys_with_metrics(Keys.list_keys(api.id))
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
       active_tab: "run"
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
       active_tab: "run"
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
       active_tab: "run"
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
     |> put_flash(:info, "#{lang} snippet copied!")}
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
    if socket.assigns.chat_loading do
      # Prevent double submit while agent is running
      {:noreply, socket}
    else
      do_agent_chat(socket, message)
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
    if socket.assigns.chat_loading do
      {:noreply, put_flash(socket, :error, "Cannot clear while agent is running")}
    else
      {:noreply,
       assign(socket,
         pending_edit: nil,
         agent_events: [],
         streaming_tokens: ""
       )}
    end
  end

  # ── Cancel Pipeline ──────────────────────────────────────────────────

  @impl true
  def handle_event("cancel_pipeline", _params, socket) do
    if ref = socket.assigns.pipeline_ref do
      Process.demonitor(ref, [:flush])
    end

    # Rollback code if this was a chat edit in progress
    socket =
      if previous = socket.assigns[:pre_edit_code] do
        socket
        |> assign(code: previous, pre_edit_code: nil)
        |> push_editor_value(previous)
        |> put_flash(:info, "Edit cancelled, code reverted")
      else
        socket
      end

    {:noreply,
     assign(socket,
       pipeline_ref: nil,
       pipeline_status: nil,
       chat_loading: false,
       streaming_tokens: ""
     )}
  end

  # ── Info & Settings Events ───────────────────────────────────────────

  @impl true
  def handle_event("update_info", %{"name" => name, "description" => description}, socket) do
    case Apis.update_api(socket.assigns.api, %{
           name: String.trim(name),
           description: String.trim(description)
         }) do
      {:ok, api} ->
        {:noreply,
         socket
         |> assign(api: api, page_title: "Edit: #{api.name}")
         |> put_flash(:info, "API info updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update API info")}
    end
  end

  @impl true
  def handle_event("save_publish_settings", params, socket) do
    attrs = %{
      method: params["method"],
      visibility: params["visibility"],
      requires_auth: params["requires_auth"] == "true"
    }

    case Apis.update_api(socket.assigns.api, attrs) do
      {:ok, api} ->
        {:noreply,
         socket
         |> assign(api: api, test_url: "/api/#{socket.assigns.org.slug}/#{api.slug}")
         |> put_flash(:info, "Settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  @impl true
  def handle_event("copy_url", _params, socket) do
    url = "/api/#{socket.assigns.org.slug}/#{socket.assigns.api.slug}"
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  @impl true
  def handle_event("copy_key", _params, socket) do
    if socket.assigns.plain_key_flash do
      {:noreply, push_event(socket, "copy_to_clipboard", %{text: socket.assigns.plain_key_flash})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("archive_api", _params, socket) do
    org = socket.assigns.org

    case Apis.get_api(org.id, socket.assigns.api.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "API not found")}

      api ->
        archive_api(api)

        {:noreply,
         socket
         |> put_flash(:info, "API archived")
         |> push_navigate(to: ~p"/apis")}
    end
  end

  # ── Metrics Events ───────────────────────────────────────────────────

  @impl true
  def handle_event("change_metrics_period", %{"period" => period}, socket)
      when is_map_key(@metric_periods, period) do
    {:noreply,
     socket
     |> assign(metrics_period: period, metrics_loaded: false)
     |> load_metrics_data()}
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
           test_error: "URL not allowed. Only /api/{username}/{slug}/* is accepted."
         )}

      {:error, :timeout} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Timeout: the request took too long."
         )}

      {:error, reason} ->
        Logger.warning("Test request failed: #{inspect(reason)}")

        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Connection error. Check if the API is compiled."
         )}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{test_ref: ref}} = socket) do
    {:noreply, assign(socket, test_loading: false, test_ref: nil)}
  end

  # Pipeline progress updates (used by validate_on_save)
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
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{doc_gen_ref: ref}} = socket) do
    {:noreply, assign(socket, doc_generating: false, doc_gen_ref: nil)}
  end

  # ── Agent Pipeline PubSub handlers ────────────────────────────────────

  @impl true
  def handle_info({:agent_run_started, %{run_id: run_id, run_type: _type}}, socket) do
    # Unsubscribe from previous run topic if exists (prevent subscription leak)
    if old_run = socket.assigns.current_run_id do
      Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{old_run}")
    end

    Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

    # Load the run struct for the header
    run = AgentConversations.get_run(run_id)

    {:noreply,
     assign(socket,
       current_run_id: run_id,
       current_run: run,
       chat_loading: true,
       active_tab: "chat"
     )}
  end

  @impl true
  def handle_info({:agent_streaming, %{delta: delta}}, socket) do
    if socket.assigns.current_run_id do
      new_tokens = socket.assigns.streaming_tokens <> delta
      {:noreply, assign(socket, streaming_tokens: new_tokens)}
    else
      # Ignore late-arriving streaming deltas after run completed
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_action, %{tool: tool_name, args: args}}, socket) do
    now = DateTime.utc_now()
    seq = length(socket.assigns.agent_events)
    normalized_args = normalize_tool_input(args)
    event = %{type: :tool_call, tool: tool_name, args: normalized_args, timestamp: now, id: seq}

    socket =
      socket
      |> assign(
        pipeline_status: agent_tool_to_status(tool_name),
        agent_events: socket.assigns.agent_events ++ [event]
      )
      |> apply_action_to_editor(tool_name, args)

    {:noreply, socket}
  end

  def handle_info({:agent_action, %{tool: tool_name}}, socket) do
    {:noreply, assign(socket, pipeline_status: agent_tool_to_status(tool_name))}
  end

  @impl true
  def handle_info({:tool_started, %{tool: tool_name}}, socket) do
    {:noreply, assign(socket, pipeline_status: agent_tool_to_status(tool_name))}
  end

  @impl true
  def handle_info({:tool_result, %{tool: tool_name, success: success} = payload}, socket) do
    content = Map.get(payload, :content, "")
    now = DateTime.utc_now()
    seq = length(socket.assigns.agent_events)

    event = %{
      type: :tool_result,
      tool: tool_name,
      success: success,
      content: content,
      timestamp: now,
      id: seq
    }

    socket =
      socket
      |> assign(agent_events: socket.assigns.agent_events ++ [event])
      |> apply_result_to_editor(tool_name, success, content)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:guardrail_triggered, %{type: type}}, socket) do
    {:noreply, put_flash(socket, :error, "Agent limit reached: #{type}")}
  end

  @impl true
  def handle_info(
        {:agent_completed, %{code: code, test_code: test_code, summary: summary, run_id: run_id}},
        socket
      ) do
    # Unsubscribe from completed run topic
    Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{run_id}")

    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    refreshed_api = api || socket.assigns.api

    # Refresh the run struct to get final timing/metrics
    completed_run =
      case AgentConversations.get_run(run_id) do
        nil -> socket.assigns.current_run
        run -> run
      end

    socket =
      socket
      |> assign(
        api: refreshed_api,
        chat_loading: false,
        current_run_id: nil,
        current_run: completed_run,
        streaming_tokens: "",
        pipeline_status: nil,
        generation_status: refreshed_api.generation_status,
        versions: Apis.list_versions(refreshed_api.id),
        validation_report: restore_validation_report(refreshed_api.validation_report),
        test_summary: derive_test_summary(refreshed_api.validation_report)
      )

    # Use code from event, or fallback to what was accumulated via tool calls
    effective_code = code || socket.assigns.code
    effective_test_code = test_code || socket.assigns.test_code

    if effective_code != "" and effective_code != nil do
      handle_agent_code_completed(
        socket,
        effective_code,
        effective_test_code,
        summary,
        refreshed_api
      )
    else
      {:noreply, put_flash(socket, :info, summary || "Agent completed")}
    end
  end

  @impl true
  def handle_info({:agent_failed, %{error: error, run_id: run_id}}, socket) do
    # Unsubscribe from failed run topic
    Phoenix.PubSub.unsubscribe(Blackboex.PubSub, "run:#{run_id}")

    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    refreshed_api = api || socket.assigns.api

    # Refresh run struct for final state
    failed_run =
      case AgentConversations.get_run(run_id) do
        nil -> socket.assigns.current_run
        run -> run
      end

    {:noreply,
     socket
     |> assign(
       api: refreshed_api,
       chat_loading: false,
       current_run_id: nil,
       current_run: failed_run,
       pipeline_status: nil,
       streaming_tokens: "",
       generation_status: refreshed_api.generation_status
     )
     |> put_flash(:error, "Agent failed: #{error}")}
  end

  @impl true
  def handle_info({:agent_message, %{role: "assistant", content: content}}, socket) do
    seq = length(socket.assigns.agent_events)

    event = %{
      type: :message,
      role: "assistant",
      content: content,
      timestamp: DateTime.utc_now(),
      id: seq
    }

    {:noreply, assign(socket, agent_events: socket.assigns.agent_events ++ [event])}
  end

  @impl true
  def handle_info({:agent_message, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:agent_started, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:doc_generated, _payload}, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

    event = %{
      type: :tool_result,
      tool: "generate_docs",
      success: true,
      content: "Documentation generated",
      timestamp: DateTime.utc_now(),
      id: length(socket.assigns.agent_events)
    }

    {:noreply,
     assign(socket,
       api: api || socket.assigns.api,
       agent_events: socket.assigns.agent_events ++ [event]
     )}
  end

  # ── Private Helpers ────────────────────────────────────────────────────

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

  defp do_accept_edit(socket, proposed_code, proposed_test_code, _instruction) do
    # Store previous code for rollback on cancel
    previous_code = socket.assigns.code
    test_code = proposed_test_code || socket.assigns.test_code

    # Agent already validated the code — apply directly
    {:noreply,
     socket
     |> assign(
       code: proposed_code,
       test_code: test_code,
       pending_edit: nil,
       pre_edit_code: previous_code,
       chat_loading: false,
       pipeline_status: nil,
       current_run_id: nil,
       streaming_tokens: ""
     )
     |> push_editor_value(proposed_code)
     |> put_flash(:info, "Change applied")}
  end

  defp do_agent_chat(socket, message) do
    org = socket.assigns.org

    case Enforcement.check_limit(org, :llm_generation) do
      {:ok, _remaining} ->
        api = socket.assigns.api
        scope = socket.assigns.current_scope

        case Apis.start_agent_edit(api, message, scope.user.id) do
          {:ok, _api_id} ->
            user_msg = %{"role" => "user", "content" => message}

            {:noreply,
             socket
             |> assign(
               chat_loading: true,
               chat_input: "",
               streaming_tokens: "",
               agent_events:
                 socket.assigns.agent_events ++
                   [
                     %{
                       type: :message,
                       role: "user",
                       content: user_msg["content"],
                       timestamp: DateTime.utc_now(),
                       id: length(socket.assigns.agent_events)
                     }
                   ]
             )}

          {:error, reason} ->
            Logger.warning("Failed to start agent edit: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Failed to start agent")}
        end

      {:error, :limit_exceeded, _details} ->
        {:noreply, put_flash(socket, :error, "LLM generation limit reached. Upgrade your plan.")}
    end
  end

  defp resolve_agent_state(api_id) do
    case AgentConversations.get_conversation_by_api(api_id) do
      nil -> {nil, nil}
      conv -> find_active_run(conv)
    end
  end

  defp find_active_run(conv) do
    active_run =
      AgentConversations.list_runs(conv.id, limit: 1)
      |> Enum.find(&(&1.status == "running"))

    if active_run,
      do: Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{active_run.id}")

    {conv, active_run && active_run.id}
  end

  defp load_conversation_events(nil), do: {[], nil}

  defp load_conversation_events(agent_conversation) do
    case AgentConversations.list_runs(agent_conversation.id, limit: 1) do
      [latest_run | _] ->
        events =
          AgentConversations.list_events(latest_run.id)
          |> Enum.map(&event_to_display/1)
          |> Enum.reject(&is_nil/1)

        {events, latest_run}

      [] ->
        {[], nil}
    end
  end

  defp event_to_display(%{event_type: "user_message"} = e) do
    %{type: :message, role: "user", content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  defp event_to_display(%{event_type: "assistant_message"} = e) do
    %{
      type: :message,
      role: "assistant",
      content: e.content,
      timestamp: e.inserted_at,
      id: e.sequence
    }
  end

  defp event_to_display(%{event_type: "tool_call"} = e) do
    args = normalize_tool_input(e.tool_input)

    %{
      type: :tool_call,
      tool: e.tool_name,
      args: args,
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  defp event_to_display(%{event_type: "tool_result"} = e) do
    %{
      type: :tool_result,
      tool: e.tool_name,
      success: e.tool_success,
      content: e.content || "",
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  defp event_to_display(%{event_type: "status_change"} = e) do
    %{type: :status, content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  defp event_to_display(_), do: nil

  defp normalize_tool_input(nil), do: %{}

  defp normalize_tool_input(args) when is_map(args) do
    Map.new(args, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_tool_input(_), do: %{}

  defp agent_tool_to_status("generate_code"), do: :generating
  defp agent_tool_to_status("compile_code"), do: :compiling
  defp agent_tool_to_status("format_code"), do: :formatting
  defp agent_tool_to_status("lint_code"), do: :linting
  defp agent_tool_to_status("generate_tests"), do: :generating_tests
  defp agent_tool_to_status("run_tests"), do: :running_tests
  defp agent_tool_to_status("submit_code"), do: :submitting
  defp agent_tool_to_status(_), do: :processing

  defp handle_agent_code_completed(socket, code, test_code, summary, api) do
    assistant_msg = %{
      "role" => "assistant",
      "content" => summary || "Code updated successfully"
    }

    completion_event = %{type: :message, role: "assistant", content: assistant_msg["content"]}
    socket = assign(socket, agent_events: socket.assigns.agent_events ++ [completion_event])

    has_previous_code = (api.source_code || "") != ""

    if has_previous_code do
      # Edit flow: show diff modal for review
      code_diff = DiffEngine.compute_diff(socket.assigns.code, code)

      {:noreply,
       socket
       |> assign(
         pending_edit: %{
           code: code,
           test_code: test_code,
           diff: code_diff,
           test_diff: [],
           explanation: summary || "Agent completed",
           instruction: summary,
           validation: nil
         }
       )
       |> put_flash(:info, summary || "Code ready for review")}
    else
      # Initial generation: agent pipeline already validated, compiled, and registered
      test_code = test_code || ""

      {:noreply,
       socket
       |> assign(code: code, test_code: test_code)
       |> push_editor_value(code)
       |> put_flash(:info, summary || "Code generated successfully")}
    end
  end

  defp archive_api(api) do
    if api.status == "published", do: Apis.unpublish(api)
    Apis.update_api(api, %{status: "archived"})
  end

  # Sync code/test_code assigns when agent tool call provides code
  defp apply_action_to_editor(socket, "compile_code", %{"code" => code}) do
    assign(socket, code: code)
  end

  defp apply_action_to_editor(socket, "run_tests", %{"code" => code, "test_code" => test_code}) do
    assign(socket, code: code, test_code: test_code)
  end

  defp apply_action_to_editor(socket, "submit_code", %{"code" => code} = args) do
    test_code = Map.get(args, "test_code", socket.assigns.test_code)
    assign(socket, code: code, test_code: test_code)
  end

  defp apply_action_to_editor(socket, _tool, _args), do: socket

  # Sync assigns when tool results contain code artifacts
  defp apply_result_to_editor(socket, "format_code", true, content) when is_binary(content) do
    assign(socket, code: content)
  end

  defp apply_result_to_editor(socket, "generate_tests", true, content) when is_binary(content) do
    assign(socket, test_code: content)
  end

  defp apply_result_to_editor(socket, _tool, _success, _content), do: socket

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

  defp lazy_load_tab(socket, "run") do
    lazy_load_tab(socket, "test")
  end

  defp lazy_load_tab(socket, "metrics") when not socket.assigns.metrics_loaded do
    load_metrics_data(socket)
  end

  defp lazy_load_tab(socket, "test") when not socket.assigns.history_loaded do
    history = Testing.list_test_requests(socket.assigns.api.id)
    assign(socket, test_history: history, history_loaded: true)
  end

  defp lazy_load_tab(socket, "keys") when not socket.assigns.keys_loaded do
    keys = enrich_keys_with_metrics(Keys.list_keys(socket.assigns.api.id))
    assign(socket, api_keys: keys, keys_loaded: true)
  end

  defp lazy_load_tab(socket, "publish") do
    api_id = socket.assigns.api.id

    metrics = %{
      count_24h: Analytics.invocations_count(api_id, period: :day),
      success_rate: Analytics.success_rate(api_id, period: :day),
      avg_latency: Analytics.avg_latency(api_id, period: :day),
      error_count: Analytics.error_count(api_id, period: :day)
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

  defp format_test_summary(test_results) when is_list(test_results) and test_results != [] do
    passed =
      Enum.count(test_results, fn item ->
        (item[:status] || item["status"]) == "passed"
      end)

    total = length(test_results)
    "#{passed}/#{total}"
  end

  defp format_test_summary(_), do: nil

  # ── Editor Tab Helpers ──────────────────────────────────────────────

  defp editor_value("code", code, _test_code), do: code
  defp editor_value("tests", _code, test_code), do: test_code

  defp count_lines(nil), do: 0
  defp count_lines(""), do: 0
  defp count_lines(code), do: code |> String.split("\n") |> length()

  defp format_json(nil), do: ""
  defp format_json(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp format_json(other), do: inspect(other)

  defp time_ago(nil), do: "never"

  defp time_ago(%NaiveDateTime{} = dt) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end

  defp time_ago(_), do: "unknown"

  defp render_markdown(nil), do: ""

  defp render_markdown(markdown) do
    case MDEx.to_html(markdown,
           extension: [
             table: true,
             strikethrough: true,
             autolink: true,
             tasklist: true,
             footnotes: true
           ],
           render: [unsafe: false],
           syntax_highlight: [
             formatter: {:html_inline, theme: "github_dark"}
           ]
         ) do
      {:ok, html} -> html
      _ -> markdown
    end
  end

  defp load_metrics_data(socket) do
    api_id = socket.assigns.api.id
    days = Map.fetch!(@metric_periods, socket.assigns.metrics_period)
    start_date = Date.add(Date.utc_today(), -days)

    rollups =
      from(r in MetricRollup,
        where: r.api_id == ^api_id and r.date >= ^start_date,
        order_by: [asc: r.date, asc: r.hour]
      )
      |> Blackboex.Repo.all()

    daily =
      rollups
      |> Enum.group_by(& &1.date)
      |> Enum.sort_by(fn {date, _} -> date end)
      |> Enum.map(fn {date, entries} ->
        %{
          label: Calendar.strftime(date, "%m/%d"),
          invocations: Enum.sum(Enum.map(entries, & &1.invocations)),
          errors: Enum.sum(Enum.map(entries, & &1.errors)),
          p95: entries |> Enum.map(& &1.p95_duration_ms) |> Enum.max(fn -> 0.0 end),
          avg_dur: entries |> Enum.map(& &1.avg_duration_ms) |> metrics_average()
        }
      end)

    total_invocations = Enum.sum(Enum.map(daily, & &1.invocations))
    total_errors = Enum.sum(Enum.map(daily, & &1.errors))

    error_rate =
      if total_invocations > 0,
        do: Float.round(total_errors / total_invocations * 100, 1),
        else: 0.0

    period_atom =
      case socket.assigns.metrics_period do
        "24h" -> :day
        "7d" -> :week
        "30d" -> :month
      end

    avg_latency = Analytics.avg_latency(api_id, period: period_atom)

    assign(socket,
      invocation_data: Enum.map(daily, &%{label: &1.label, value: &1.invocations}),
      latency_data: Enum.map(daily, &%{label: &1.label, value: round(&1.p95)}),
      error_data: Enum.map(daily, &%{label: &1.label, value: &1.errors}),
      total_invocations: total_invocations,
      total_errors: total_errors,
      error_rate: error_rate,
      avg_latency: avg_latency,
      metrics_loaded: true
    )
  rescue
    error ->
      Logger.error("Failed to load metrics: #{Exception.message(error)}")

      assign(socket,
        invocation_data: [],
        latency_data: [],
        error_data: [],
        total_invocations: 0,
        total_errors: 0,
        error_rate: 0.0,
        avg_latency: 0,
        metrics_loaded: true
      )
  end

  defp metrics_average([]), do: 0.0
  defp metrics_average(list), do: Enum.sum(list) / length(list)

  defp enrich_keys_with_metrics(keys) do
    Enum.map(keys, fn key ->
      if key.revoked_at do
        Map.put(key, :metrics, nil)
      else
        Map.put(key, :metrics, Keys.key_metrics(key.id))
      end
    end)
  end

  defp derive_test_summary(nil), do: nil

  defp derive_test_summary(report) when is_map(report) do
    format_test_summary(report["test_results"] || [])
  end

  defp restore_validation_report(nil), do: nil

  defp restore_validation_report(report) when is_map(report) do
    %{
      compilation: safe_to_atom(report["compilation"]),
      compilation_errors: report["compilation_errors"] || [],
      format: safe_to_atom(report["format"]),
      format_issues: report["format_issues"] || [],
      credo: safe_to_atom(report["credo"]),
      credo_issues: report["credo_issues"] || [],
      tests: safe_to_atom(report["tests"]),
      test_results: report["test_results"] || [],
      overall: safe_to_atom(report["overall"])
    }
  end

  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass

  defp test_summary_class(summary) do
    if String.contains?(summary, "/") do
      [passed, total] = String.split(summary, "/")
      if passed == total, do: "bg-green-100 text-green-700", else: "bg-red-100 text-red-700"
    else
      "bg-gray-100 text-gray-600"
    end
  end
end
