# AGENTS.md — LiveView Layer

This document is the authoritative guide for building interactive pages in this application.
All new LiveViews MUST follow these patterns. Read every section before writing code.

---

## CRITICAL RULES

1. **LiveViews MUST be thin.** All business logic belongs in domain contexts under
   `apps/blackboex/lib/blackboex/`. A LiveView only: loads data, handles events,
   updates assigns, and renders. Nothing else.

2. **NEVER write business logic in a LiveView.** Validation, authorization, DB queries,
   and computations go in the domain. The LiveView calls a context function and reacts
   to the result.

3. **ALL UI MUST use components from `components/`.** Never write raw HTML that belongs
   in a reusable component. Import the component module, then call its function component.

4. **Always use `current_scope` from `socket.assigns` for authorization and scoping.**
   The `current_scope` struct carries both `user` and `organization`. Every data fetch
   that belongs to an org MUST be scoped through `org.id`. Every destructive action MUST
   go through `Policy.authorize_and_track/3` first.

5. **Never call `Repo` directly from a LiveView.** The one exception in `SettingsLive`
   (raw Repo query for members) is a known violation that should be migrated to a context
   function. New code must not replicate this pattern.

6. **Every public function must have a `@spec`.**

---

## Layout Selection

| Layout      | When to use                                               | Router `live_session` |
|-------------|-----------------------------------------------------------|-----------------------|
| `:app`      | All authenticated app pages: dashboard, lists, settings   | `:require_authenticated_user` |
| `:editor`   | Full-screen API editor (all `/apis/:id/edit/*` routes)    | `:editor` |
| `:auth`     | Login, registration, email confirmation pages             | `:current_user` |

The layout is set at the `live_session` level in the router — **not** in the LiveView
itself. When adding a new route, place it in the correct `live_session` block.

---

## Standard Mount Pattern

```elixir
@impl true
def mount(_params, _session, socket) do
  org = socket.assigns.current_scope.organization

  socket =
    if org do
      # 1. Load data via domain contexts, scoped to org
      data = MyContext.list_things(org.id)

      # 2. Subscribe to PubSub if real-time updates are needed (connected? guard)
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Blackboex.PubSub, "some_topic:#{org.id}")
      end

      assign(socket, things: data, page_title: "My Page")
    else
      # 3. Handle nil org with safe empty state — never crash
      assign(socket, things: [], page_title: "My Page")
    end

  {:ok, socket}
end
```

Key rules:
- Always check `org` before fetching org-scoped data.
- Wrap PubSub subscriptions in `connected?(socket)` to skip on static render.
- Always set `page_title`.
- Return `{:ok, socket}` — never `{:ok, socket, temporary_assigns: [...]}` unless you
  understand the implications for component re-rendering.

### handle_params pattern (for tab/query-param driven pages)

```elixir
@impl true
def handle_params(params, _uri, socket) do
  tab = Map.get(params, "tab", "default")
  tab = if tab in @valid_tabs, do: tab, else: "default"

  socket =
    socket
    |> assign(:active_tab, tab)
    |> load_tab_data(tab)

  {:noreply, socket}
end
```

Use `handle_params` (not `mount`) when page state is driven by URL query params or path
segments that change via `push_patch`. See `SettingsLive` for the tab pattern.

---

## Standard handle_event Pattern

```elixir
@impl true
def handle_event("delete_thing", %{"id" => id}, socket) do
  scope = socket.assigns.current_scope
  org   = scope.organization

  # 1. Authorize via Policy before any data access
  # 2. Load the resource scoped to org (IDOR prevention)
  # 3. Call the context function
  with :ok <- Policy.authorize_and_track(:thing_delete, scope, org),
       thing when not is_nil(thing) <- MyContext.get_thing(org.id, id),
       {:ok, _thing} <- MyContext.delete_thing(thing) do
    things = MyContext.list_things(org.id)
    {:noreply, socket |> assign(things: things) |> put_flash(:info, "Deleted.")}
  else
    {:error, _reason} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    nil                -> {:noreply, put_flash(socket, :error, "Not found.")}
    {:error, _cs}      -> {:noreply, put_flash(socket, :error, "Could not delete.")}
  end
end
```

Rules:
- Use `with` for chained operations that can each fail.
- `Policy.authorize_and_track/3` MUST be the first step for any mutating action.
- Always fetch the resource scoped to `org.id` — never fetch by bare `id` from external
  input. This prevents IDOR.
- Use `put_flash(:info, ...)` on success, `put_flash(:error, ...)` on failure.
- Use `push_navigate` for full navigation to a new URL.
- Use `push_patch` to update the current URL without a full mount cycle (e.g., tab changes,
  query params).
- Whitelist event parameter values where possible (see `@valid_periods ~w(24h 7d 30d)`
  pattern in `DashboardLive` and `when period in @valid_periods` guard).

---

## Standard handle_info Pattern (PubSub)

```elixir
@impl true
def handle_info({:thing_updated, %{thing: thing}}, socket) do
  # Pattern match on the exact tuple shape broadcast by the context
  {:noreply, assign(socket, thing: thing)}
end

def handle_info({:thing_deleted, %{id: id}}, socket) do
  things = Enum.reject(socket.assigns.things, &(&1.id == id))
  {:noreply, assign(socket, things: things)}
end

# Catch-all to silence unrelated messages (required when using Task.async)
def handle_info(_msg, socket), do: {:noreply, socket}
```

Rules:
- Subscribe on connected mount only: `if connected?(socket), do: Phoenix.PubSub.subscribe(...)`.
- Pattern match on the specific tuple shape — never use a wildcard as the only clause.
- Always include a catch-all `handle_info(_msg, socket)` when a LiveView also handles
  Task results (otherwise unrelated DOWN messages raise).

---

## Async Pattern — Task.async in LiveView

Use `Task.async` for any blocking IO or external calls (LLM, HTTP, etc.).
**NEVER use `send(self(), :do_blocking_work)` for IO.** That blocks the LiveView process.

```elixir
def handle_event("generate_docs", _params, socket) do
  task = Task.async(fn -> MyContext.expensive_operation(socket.assigns.api) end)
  {:noreply, assign(socket, loading: true, task_ref: task.ref)}
end

@impl true
def handle_info({ref, {:ok, result}}, socket) when ref == socket.assigns.task_ref do
  Process.demonitor(ref, [:flush])
  {:noreply, assign(socket, loading: false, task_ref: nil, result: result)}
end

def handle_info({ref, {:error, _reason}}, socket) when ref == socket.assigns.task_ref do
  Process.demonitor(ref, [:flush])
  {:noreply, socket |> assign(loading: false, task_ref: nil) |> put_flash(:error, "Failed.")}
end

def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
    when ref == socket.assigns.task_ref do
  {:noreply, assign(socket, loading: false, task_ref: nil)}
end
```

Rules: store `task.ref` in assigns; call `Process.demonitor(ref, [:flush])` in success/error;
handle `{:DOWN, ref, ...}` for crashes; drive loading state from assigns.

---

## Form Patterns

```elixir
# In mount:
changeset = MyContext.change_thing(%Thing{})
assign(socket, form: to_form(changeset, as: "thing"))

# Validate event:
def handle_event("validate", %{"thing" => params}, socket) do
  changeset = %Thing{} |> MyContext.change_thing(params) |> Map.put(:action, :validate)
  {:noreply, assign(socket, form: to_form(changeset, as: "thing"))}
end

# Save event:
def handle_event("save", %{"thing" => params}, socket) do
  case MyContext.create_thing(params) do
    {:ok, _thing}                      -> {:noreply, push_navigate(socket, to: ~p"/things")}
    {:error, %Ecto.Changeset{} = cs}   -> {:noreply, assign(socket, form: to_form(cs, as: "thing"))}
  end
end
```

Rules: always use `to_form/2`; set `:action` on changeset in `validate` so errors display
immediately; use `phx-change="validate"` + `phx-submit="save"`; never render error messages
manually — `<.input field={@form[:field]} />` handles it.

---

## Modal Pattern

```elixir
# In assigns:
assign(socket, show_modal: false)

# Toggle event:
def handle_event("open_modal", _params, socket),
  do: {:noreply, assign(socket, show_modal: true)}

def handle_event("close_modal", _params, socket),
  do: {:noreply, assign(socket, show_modal: false)}

# In render:
<.modal show={@show_modal} on_close="close_modal" title="Create Thing">
  <form phx-submit="create_thing">
    ...
  </form>
</.modal>
```

---

## LiveComponent Pattern

Use `live_component` for complex, stateful sub-sections of a LiveView that have their
own event handling (e.g., `ChatPanel`, `RequestBuilder`, `ResponseViewer` in the editor).

```elixir
<.live_component
  module={BlackboexWeb.Components.Editor.ChatPanel}
  id="chat-panel"
  events={@agent_events}
  loading={@chat_loading}
  api_id={@api.id}
/>
```

Rules:
- Always provide a stable `id`.
- Pass only the data the component needs — avoid passing the entire `assigns` map.
- LiveComponents send events to their parent LiveView using `send(self(), ...)` or
  `Phoenix.PubSub`. They do NOT call context functions themselves — that still belongs
  to the parent LiveView or a domain context.

---

## LiveComponent Required Assigns

These three modules use `use BlackboexWeb, :live_component` and are rendered with
`<.live_component module={...} id="...">`. All listed assigns must be passed; omitting
any will raise a `KeyError` at render time because none implement `update/2` with defaults.

| Component | Module | Required Assigns | Optional Assigns |
|-----------|--------|-----------------|-----------------|
| `ChatPanel` | `BlackboexWeb.Components.Editor.ChatPanel` | `events`, `input`, `loading`, `api_id`, `pending_edit`, `streaming_tokens`, `run`, `template_type` | `pipeline_status` |
| `RequestBuilder` | `BlackboexWeb.Components.Editor.RequestBuilder` | `method`, `url`, `params`, `headers`, `body_json`, `body_error`, `api_key`, `loading`, `active_tab` | — |
| `ResponseViewer` | `BlackboexWeb.Components.Editor.ResponseViewer` | `response`, `loading`, `error`, `violations`, `response_tab` | — |

### ChatPanel assign details

| Assign | Type | Notes |
|--------|------|-------|
| `events` | `list` | List of agent event maps from `@agent_events`; may be `[]` |
| `input` | `string` | Current chat input field value |
| `loading` | `boolean` | `true` while the pipeline is running (combine `@chat_loading` and `@generation_status` check) |
| `api_id` | `string` | API UUID, used for routing events back to the parent |
| `pending_edit` | `map \| nil` | Pending diff proposal; `nil` when nothing is pending |
| `streaming_tokens` | `string` | Pass `""` when not loading; pass `@streaming_tokens` when `@chat_loading` is `true` |
| `run` | `map \| nil` | The current `Run` struct for displaying the run summary |
| `template_type` | `string` | Used by `quick_actions/1` helper to populate suggestion pills |
| `pipeline_status` | `string \| nil` | Optional; displayed as status label in the header |

### RequestBuilder assign details

| Assign | Type | Notes |
|--------|------|-------|
| `method` | `string` | HTTP method: `"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"` |
| `url` | `string` | Full URL of the API endpoint; rendered read-only |
| `params` | `list` | List of `%{id, key, value}` maps for query params |
| `headers` | `list` | List of `%{id, key, value}` maps for request headers |
| `body_json` | `string` | JSON string for request body (shown in Body tab) |
| `body_error` | `string \| nil` | JSON parse error message; `nil` when body is valid |
| `api_key` | `string` | Value shown in the Auth tab input |
| `loading` | `boolean` | Disables Send button and shows spinner while request is in flight |
| `active_tab` | `string` | Active sub-tab: `"params"`, `"headers"`, `"body"`, or `"auth"` |

### ResponseViewer assign details

| Assign | Type | Notes |
|--------|------|-------|
| `response` | `map \| nil` | Response map with keys `status` (integer), `duration_ms`, `body`, `headers`; `nil` before first request |
| `loading` | `boolean` | Shows spinner when `true` |
| `error` | `string \| nil` | Error message shown as destructive alert; `nil` on success |
| `violations` | `list` | Schema violation list; `[]` = valid; shows warning badge with count when non-empty |
| `response_tab` | `string` | Active sub-tab: `"body"` or `"headers"` |

---

## Function Components in `components/editor/`

These are **not** LiveComponents — they are stateless function components rendered with
`<.function_name>`. They do NOT use `id=` and do NOT handle events themselves.

### Editor shell components (import `BlackboexWeb.Components.Editor.*`)

| Function | Module | Required attrs | Optional attrs |
|----------|--------|----------------|----------------|
| `<.editor_toolbar>` | `Editor.Toolbar` | `api` | `selected_version`, `generation_status` |
| `<.command_palette>` | `Editor.CommandPalette` | `api` | `open`, `query`, `selected_index` |
| `<.validation_dashboard>` | `Editor.ValidationDashboard` | — | `report`, `loading` |
| `<.status_bar>` | `Editor.StatusBar` | `api` | `versions`, `selected_version` |
| `<.right_panel>` | `Editor.RightPanel` | `mode` | — (requires `:inner_block` slot) |
| `<.bottom_panel>` | `Editor.BottomPanel` | — | `active_tab`, `validation_report` (requires `:inner_block` slot) |
| `<.code_viewer>` | `Editor.CodeViewer` | `code` | `label`, `class` |
| `<.file_tree>` | `Editor.FileTree` | `files` | `selected_path`, `generating` |
| `<.file_editor>` | `Editor.FileEditor` | — | `file`, `live_content`, `streaming`, `read_only`, `class` |
| `<.editor_page_header>` | `Editor.PageHeader` | `title`, `back_path` | `back_label`, `class` (slots: `:badge`, `:actions`) |
| `<.save_indicator>` | `Editor.SaveIndicator` | — | `status` (`:saved` \| `:saving` \| `:unsaved`) |

### Playground/page sidebar components

| Function | Module | Required attrs | Optional attrs |
|----------|--------|----------------|----------------|
| `<.playground_tree>` | `Editor.PlaygroundTree` | `playgrounds` | `current_playground_id` |
| `<.page_tree>` | `Editor.PageTree` | `tree` | `current_page_id`, `expanded_ids` |
| `<.execution_history>` | `Editor.ExecutionHistory` | `executions` | `selected_execution_id` |
| `<.terminal_output>` | `Editor.TerminalOutput` | — | `output`, `status`, `duration_ms`, `run_number` |

### Playground chat panel (function component, NOT a LiveComponent)

`PlaygroundChatPanel` (`Editor.PlaygroundChatPanel`) uses `use BlackboexWeb, :html` — it is
a **function component**, not a LiveComponent. Render it with `<.playground_chat_panel>` after
importing the module.

| attr | Required | Default | Notes |
|------|----------|---------|-------|
| `messages` | yes | — | List of `%{role, content}` maps; roles: `"user"`, `"assistant"`, `"system"` |
| `input` | no | `""` | Current input field value |
| `loading` | no | `false` | Shows thinking indicator when `true` |
| `current_stream` | no | `nil` | Streaming token string; shown as streaming code block |

Event contract (parent must handle): `phx-submit="send_chat"` (field: `"message"`),
`phx-change="chat_input_change"`, `phx-click="new_chat"`.

---

## Editor Tab LiveViews — The Shared Pattern

All `/apis/:id/edit/*` LiveViews share a common structure enforced by `Edit.Shared`.

### Mount

Every edit tab calls `Shared.load_api/2` as its first mount step:

```elixir
@impl true
def mount(params, _session, socket) do
  case Shared.load_api(socket, params) do
    {:ok, socket} ->
      # socket already has: api, org, page_title, versions, selected_version,
      # generation_status, validation_report, test_summary, command_palette_*
      {:ok, assign(socket, tab_specific_data: ...)}

    {:error, socket} ->
      # Shared already put_flash + push_navigate to /apis
      {:ok, socket}
  end
end
```

`Shared.load_api/2` verifies org membership, fetches the API, and sets all common assigns.

### Command Palette Delegation

Every edit tab delegates command palette events to `Shared.handle_command_palette/3`:

```elixir
@command_palette_events ~w(toggle_command_palette close_panels command_palette_search
  command_palette_navigate command_palette_exec command_palette_exec_first)

@impl true
def handle_event(event, params, socket) when event in @command_palette_events do
  Shared.handle_command_palette(event, params, socket)
end
```

### Shell Render

Every edit tab wraps its content in `EditorShell`:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <.editor_shell {shared_shell_assigns(assigns)} active_tab="mytab">
    <!-- tab content -->
  </.editor_shell>
  """
end

defp shared_shell_assigns(assigns) do
  Map.take(assigns, [
    :api, :versions, :selected_version, :generation_status,
    :validation_report, :test_summary,
    :command_palette_open, :command_palette_query, :command_palette_selected
  ])
end
```

---

## LiveView Catalog

| LiveView | Layout | Purpose | Key Events |
|----------|--------|---------|------------|
| `DashboardLive` | app | Org summary, API stats, usage gauges, LLM usage, recent activity. Period selection updates metrics charts. | `set_period` |
| `ApiLive.Index` | app | Lists all org APIs with 24h stats. Inline create modal triggers agent generation on submit. | `search`, `delete`, `open_create_modal`, `close_create_modal`, `create_api` |
| `ApiLive.Show` | app | Redirect shim to `/apis/:id/edit`. Kept for backward compatibility. | — |
| `ApiLive.New` | app | Redirect shim to `/apis`. Creation now happens via modal on Index. | — |
| `ApiLive.Analytics` | app | Redirect shim to `/apis/:id/edit`. Kept for backward compatibility. | — |
| `ApiLive.Edit.ChatLive` | editor | AI agent chat with 3-panel workspace layout (file tree left, file editor center, chat right): conversation history, streaming tokens, pipeline status, pending diff review. PubSub: `api:#{id}`, `run:#{run_id}`. | `send_chat`, `accept_edit`, `reject_edit`, `quick_action`, `clear_conversation`, `cancel_pipeline` |
| `ApiLive.Edit.CodeLive` | editor | Read-only syntax-highlighted view of current API source code. | command palette only |
| `ApiLive.Edit.TestsLive` | editor | Read-only syntax-highlighted view of generated test code. | command palette only |
| `ApiLive.Edit.ValidationLive` | editor | `ValidationDashboard` component: compilation, format, credo, test pass/fail from `validation_report`. | command palette only |
| `ApiLive.Edit.DocsLive` | editor | Renders API markdown docs. Regenerate via `Task.async` -> `DocGenerator.generate/1`. | `generate_docs` |
| `ApiLive.Edit.RunLive` | editor | HTTP request builder + response viewer. Request history, code snippets. `Task.async` -> `RequestExecutor.execute/2`. | `send_request`, `quick_test`, `generate_sample`, `copy_snippet`, `update_test_*`, `add/remove_param`, `add/remove_header`, `switch_*_tab`, `load_history_item`, `clear_history` |
| `ApiLive.Edit.MetricsLive` | editor | Time-series charts (invocations, latency, errors) from rollup table with period switching. Shows recent error log. | `change_metrics_period` |
| `ApiLive.Edit.PublishLive` | editor | Unified deployment tab: publish/unpublish, version timeline with LIVE badge, publish-specific-version, keys summary with link to /api-keys, 24h metrics, auth settings, docs links. | `publish`, `unpublish`, `publish_version`, `view_version`, `clear_version_view`, `save_publish_settings`, `copy_url` |
| `ApiLive.Edit.InfoLive` | editor | Edit API name/description, code stats, param schema, examples, archive. | `update_info`, `archive_api`, `copy_url` |
| `ProjectLive.ApiKeys` | app | Project-scoped API key list with 'API Keys' tab active. Create modal, plain-key banner shown once after creation. Cross-project API IDs are rejected. Replaces the removed org-wide `ApiKeyLive.Index`. Key assigns: `keys`, `apis`, `show_create_modal`, `plain_key_flash`, `org`, `project`. | `toggle_create_modal`, `create_key`, `dismiss_flash` |
| `ProjectLive.ApiKeyShow` | app | Project-scoped API key detail view with usage metrics, period switching. Rotate and revoke actions. Ownership enforced (key must belong to the URL project + org). Back link returns to `ProjectLive.ApiKeys`. Key assigns: `key`, `metrics`, `period`, `plain_key_flash`, `confirm`, `org`, `project`. | `set_period`, `revoke`, `rotate`, `dismiss_flash`, `request_confirm`, `dismiss_confirm`, `execute_confirm` |
| `ProjectLive.EnvVars` | app | Project env vars CRUD (`kind="env"` only). Values are always masked (`••••••••`) after save — plaintext only shown in create/update inputs. Name is immutable after creation. Delete requires confirmation. Key assigns: `env_vars`, `show_create_modal`, `edit_id`, `edit_form`, `delete_id`, `create_form`, `org`, `project`. | `open_create_modal`, `close_create_modal`, `validate_create`, `create_env_var`, `open_edit_modal`, `close_edit_modal`, `validate_update`, `update_env_var`, `open_delete_modal`, `close_delete_modal`, `confirm_delete_env_var` |
| `ProjectLive.LlmIntegrations` | app | Project-scoped LLM integration key (Anthropic). Not-configured state shows create form; configured state shows masked key (`sk-ant-...xxxx`), Update, Remove and Test Connection actions. Test uses `LLM.Config.client_for_project/1` + `generate_text/2` with short ping prompt. Key assigns: `configured_key`, `form`, `test_state`, `test_message`, `org`, `project`. | `save_key`, `delete_key`, `test_connection` |
| `BillingLive.Plans` | app | Plan cards with current usage. Redirects to Stripe checkout for upgrades. | `choose_plan` |
| `BillingLive.Manage` | app | Current subscription details. Redirects to Stripe portal for management. | `manage` |
| `SettingsLive` | app | Tabbed settings (profile, organization, billing, security). Tab state URL-driven via `handle_params`. | navigation only via `<.link patch=...>` |
| `UserLive.Registration` | auth | Email registration form. `phx-change="validate"` + `phx-submit="save"`. | `validate`, `save` |
| `UserLive.Login` | auth | Dual-mode login: password form (`phx-trigger-action`) and magic link form. | `submit_password`, `submit_magic` |
| `OrgMemberLive.Index` | app | Organization member list. Owners can change roles (`owner`/`admin`/`member`) via inline select and remove members. Guards against removing the last owner. Key assigns: `members`, `is_owner`, `org`. | `update_role`, `remove_member` |
| `ProjectLive.Index` | app | Lists all projects for the current organization. Row-click navigates to the project dashboard. Links to `ProjectLive.New`. Key assigns: `projects`, `org`. | — |
| `ProjectLive.New` | app | Create a new project (name → auto-slug). On success navigates to the project dashboard. Key assigns: `form`. | `create` |
| `ProjectMemberLive.Index` | app | Project member management. Shows two sections: explicit (direct) members with inline role editor, and implicit members (org owners/admins with automatic access). Project admins can add eligible org members, change roles (`admin`/`editor`/`viewer`), and remove direct members. Key assigns: `explicit_members`, `implicit_members`, `eligible_members`, `is_admin`, `project`, `org`. | `add_member`, `update_role`, `remove_member` |
| `ProjectSettingsLive` | app | Project settings form. Admins can rename a project and edit its description; slug is shown read-only. Uses `phx-change="validate"` + `phx-submit="save"`. Key assigns: `project`, `form`. | `validate`, `save` |

---

## Template Helper Functions

Private helpers (`defp`) in a LiveView are only for:
1. **Formatting values for display** — e.g., `format_latency/1`, `format_number/1`,
   `relative_time/1`. These are pure functions, no side effects.
2. **Data extraction from assigns** — e.g., `shared_shell_assigns/1`, `load_tab_data/2`.
3. **Inline component definitions** — `attr`/`slot` + `defp name(assigns)` for small,
   single-use components local to this LiveView.

Never put domain logic (validations, computations that belong in a context) in private
helpers.

---

## File Placement

```
live/
  dashboard_live.ex              # top-level LiveViews
  settings_live.ex
  api_live/
    index.ex                     # /apis
    show.ex                      # redirect shim
    new.ex                       # redirect shim
    analytics.ex                 # redirect shim
    edit/
      shared.ex                  # shared mount + command palette logic
      editor_shell.ex            # shared shell HTML component (use BlackboexWeb, :html)
      helpers.ex                 # shared template helpers
      chat_live.ex               # /apis/:id/edit/chat
      code_live.ex               # /apis/:id/edit/code
      tests_live.ex              # /apis/:id/edit/tests
      validation_live.ex         # /apis/:id/edit/validation
      docs_live.ex               # /apis/:id/edit/docs
      run_live.ex                # /apis/:id/edit/run
      metrics_live.ex            # /apis/:id/edit/metrics
      publish_live.ex            # /apis/:id/edit/publish
      info_live.ex               # /apis/:id/edit/info
  api_key_live/
    index.ex
    show.ex
  billing_live/
    plans.ex
    manage.ex
  user_live/
    registration.ex
    login.ex
    settings.ex
    confirmation.ex
```

New LiveViews for a domain area go in the corresponding subdirectory. Shared logic for
a subdirectory group goes in a `shared.ex` module in that subdirectory (see `Edit.Shared`).

---

## Recurring Patterns

These patterns appear in multiple LiveViews. Copy them verbatim — do not invent variants.

---

### Pattern: Confirm Dialog

**When to use:** Any destructive action (delete, archive, revoke) that requires a user
confirmation step before executing — replaces inline `window.confirm`.

**Files using this:** `ApiLive.Index`, `FlowLive.Index`

```elixir
# In mount assigns:
confirm: nil

# Event handlers:
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

# Trigger from a button (passes the real event name + resource id as phx-value-*):
<.button
  phx-click="request_confirm"
  phx-value-action="delete"
  phx-value-id={item.id}
  variant="link"
  size="sm"
  class="link-destructive"
>
  Delete
</.button>

# In render (conditional — only mounted when confirm is non-nil):
<.confirm_dialog
  :if={@confirm}
  title={@confirm.title}
  description={@confirm.description}
  variant={@confirm[:variant] || :warning}
  confirm_label={@confirm[:confirm_label] || "Confirm"}
/>
```

The `execute_confirm` handler re-dispatches to the real event handler (e.g. `"delete"`)
with the stored `meta` map as params, so the real handler needs no changes.
`IndexHelpers.build_confirm/2` lives in the LiveView's own `index_helpers.ex` module and
returns a map with at minimum `%{event:, meta:, title:, description:}`.

---

### Pattern: Create Modal with Template Selection

**When to use:** Index pages where items can be created either from a curated template
library or from a blank/description form — a two-mode creation flow inside a modal.

**Files using this:** `ApiLive.Index`, `FlowLive.Index`

```elixir
# In mount assigns:
show_create_modal: false,
creation_mode: :template,       # :template | :description  (ApiLive uses :description; FlowLive uses :blank)
selected_template: nil,
template_categories: [],        # loaded lazily on open_create_modal
active_category: nil,
create_form: to_form(%{"name" => "", "description" => ""}),
create_error: nil

# Open — loads categories lazily, resets all modal state:
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

# Switch creation mode:
@impl true
def handle_event("switch_to_template", _params, socket) do
  {:noreply, assign(socket, creation_mode: :template, selected_template: nil)}
end

@impl true
def handle_event("switch_to_description", _params, socket) do
  {:noreply, assign(socket, creation_mode: :description, selected_template: nil)}
end

# Filter by category (clears selection when switching):
@impl true
def handle_event("set_active_category", %{"category" => cat}, socket) do
  {:noreply, assign(socket, active_category: cat, selected_template: nil)}
end

# Select a template (pre-fills name if blank):
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

# Creation handler — validates, then delegates to a private helper:
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
```

The modal component itself is a separate function component (e.g. `<.create_modal>` or
`<.create_flow_modal>`) imported from a sibling `components/` file. Pass all modal-related
assigns to it; keep event logic in the LiveView.

---

### Pattern: Search with Scope Filtering

**When to use:** Index pages that support a live search box where results must be
re-fetched from the database (not filtered client-side), with results scoped differently
depending on whether the current scope has a project or only an org.

**Files using this:** `ApiLive.Index`, `FlowLive.Index`

```elixir
# In mount assigns:
search: ""

# Simple case (org-only scope, as in FlowLive.Index):
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

# Multi-scope case (project vs org, as in ApiLive.Index):
@impl true
def handle_event("search", %{"search" => query}, socket) do
  query = String.slice(query, 0, 200)
  scope = socket.assigns.current_scope
  org = scope.organization

  api_rows =
    cond do
      scope.project ->
        DashboardQueries.list_apis_with_stats_for_project(scope.project.id, search: query)

      org ->
        DashboardQueries.list_apis_with_stats(org.id, search: query)

      true ->
        []
    end

  {:noreply, assign(socket, api_rows: api_rows, search: query)}
end

# In render — always use phx-debounce to throttle DB calls:
<.form :let={_f} for={%{}} as={:search} phx-change="search" class="w-full">
  <.input
    type="text"
    name="search"
    value={@search}
    placeholder="Search by name or description..."
    phx-debounce="300"
  />
</.form>
```

Key rules:
- Truncate query to 200 chars with `String.slice(query, 0, 200)` before passing to the DB.
- Use `phx-debounce="300"` on the search input — never call the DB on every keystroke.
- Use `cond` (not nested `if`) when the scope check has more than two branches.
- Pass `search: query` as a keyword option to the context list function — keep filtering
  in the `*Queries` module, not in the LiveView.
