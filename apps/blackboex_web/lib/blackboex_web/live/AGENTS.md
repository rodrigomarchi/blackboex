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
| `ApiLive.Edit.VersionsLive` | editor | Lists all API versions. View historical code, rollback (creates new version). | `view_version`, `clear_version_view`, `rollback` |
| `ApiLive.Edit.RunLive` | editor | HTTP request builder + response viewer. Request history, code snippets. `Task.async` -> `RequestExecutor.execute/2`. | `send_request`, `quick_test`, `generate_sample`, `copy_snippet`, `update_test_*`, `add/remove_param`, `add/remove_header`, `switch_*_tab`, `load_history_item`, `clear_history` |
| `ApiLive.Edit.MetricsLive` | editor | Time-series charts (invocations, latency, errors) from rollup table with period switching. Shows recent error log. | `change_metrics_period` |
| `ApiLive.Edit.KeysLive` | editor | Manages API keys: create, rotate, revoke. Shows key metrics. | `create_key`, `revoke_key`, `rotate_key`, `dismiss_key_flash`, `copy_key` |
| `ApiLive.Edit.PublishLive` | editor | API publication lifecycle (publish/unpublish). 24h metrics, HTTP method, visibility, auth settings. | `publish`, `unpublish`, `save_publish_settings`, `copy_url` |
| `ApiLive.Edit.InfoLive` | editor | Edit API name/description, code stats, param schema, examples, archive. | `update_info`, `archive_api`, `copy_url` |
| `ApiKeyLive.Index` | app | Lists all org API keys. Create modal with API selector. Shows plain key once after creation. | `toggle_create_modal`, `create_key`, `dismiss_flash` |
| `ApiKeyLive.Show` | app | Detailed key view with usage metrics, period switching. Rotate and revoke actions. | `set_period`, `revoke`, `rotate`, `dismiss_flash` |
| `BillingLive.Plans` | app | Plan cards with current usage. Redirects to Stripe checkout for upgrades. | `choose_plan` |
| `BillingLive.Manage` | app | Current subscription details. Redirects to Stripe portal for management. | `manage` |
| `SettingsLive` | app | Tabbed settings (profile, organization, billing, security). Tab state URL-driven via `handle_params`. | navigation only via `<.link patch=...>` |
| `UserLive.Registration` | auth | Email registration form. `phx-change="validate"` + `phx-submit="save"`. | `validate`, `save` |
| `UserLive.Login` | auth | Dual-mode login: password form (`phx-trigger-action`) and magic link form. | `submit_password`, `submit_magic` |

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
      versions_live.ex           # /apis/:id/edit/versions
      run_live.ex                # /apis/:id/edit/run
      metrics_live.ex            # /apis/:id/edit/metrics
      keys_live.ex               # /apis/:id/edit/keys
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
