# LiveView on_mount Hooks

## Overview

`on_mount` hooks are called once per LiveView mount (and once per live navigation between views within the same `live_session`). They run before `mount/3` on the LiveView itself, in the order declared in the `live_session` block. Each hook receives `(action, params, session, socket)` and must return either `{:cont, socket}` to continue mounting or `{:halt, socket}` to abort (e.g. redirect).

All hooks in this directory are registered exclusively via `live_session ... on_mount: [...]` in `router.ex`. Never call them directly from a LiveView's `mount/3`.

---

## Hook Catalog

### `SetOrganization` (`hooks/set_organization.ex`)

**Purpose:** Resolves the current organization from the Phoenix `session` (key `"organization_id"`) and writes it into `current_scope`. Falls back to the user's first organization when the session has no ID, the org no longer exists, or the user lost membership.

**Sets assigns:**
- `socket.assigns.current_scope` — enriched with `organization` and `membership` fields via `Scope.with_organization/3`

**Use when:** Routes that are NOT URL-prefixed with `/orgs/:org_slug` but still need an org context (the legacy flat namespace: `/apis`, `/flows`, `/users/settings`, `/admin`).

**Do NOT use when:** The route is under `/orgs/:org_slug/` — use `SetOrganizationFromUrl` instead so the URL slug is the source of truth.

**Side effects:** None. Never redirects; always returns `{:cont, socket}`.

---

### `SetOrganizationFromUrl` (`hooks/set_organization_from_url.ex`)

**Purpose:** Reads `:org_slug` from URL params and resolves the matching organization + membership, writing both into `current_scope`. Redirects to `/users/log-in` when the slug is invalid or the user has no membership in that org.

**Sets assigns:**
- `socket.assigns.current_scope` — enriched with `organization` and `membership` via `Scope.with_organization/3`

**Use when:** All routes under `/orgs/:org_slug/`. Must be listed before any hook that depends on `current_scope.organization` (e.g. `SetProjectFromUrl`, `SetPreferredProject`).

**Do NOT use when:** The route has no `:org_slug` param — use `SetOrganization` instead.

**Side effects:** Redirects to `/users/log-in` (`:halt`) if the org slug is not found or user is not a member.

---

### `SetProjectFromUrl` (`hooks/set_project_from_url.ex`)

**Purpose:** Reads `:project_slug` from URL params and resolves the matching project, enforcing access control. Org owners and admins get implicit access (no project membership row required). Regular members must have an explicit `ProjectMembership`.

**Requires:** `SetOrganizationFromUrl` (or equivalent) must have run first so `current_scope` already carries `organization` and `membership`.

**Sets assigns:**
- `socket.assigns.current_scope` — enriched with `project` and `project_membership` via `Scope.with_project/3`; `project_membership` is `nil` for org owners/admins

**Use when:** All routes under `/orgs/:org_slug/projects/:project_slug/`.

**Do NOT use when:** Org-scoped routes that have no `:project_slug` param — use `SetPreferredProject` there to populate a best-guess project for sidebar context.

**Side effects:** Redirects to `/users/log-in` (`:halt`) if the project slug is not found or the user has no access.

---

### `SetPreferredProject` (`hooks/set_preferred_project.ex`)

**Purpose:** On org-level routes (where no `:project_slug` exists), populates `current_scope` with the user's last-visited project for the current org, falling back to the default/first accessible project. Allows the sidebar to keep showing a meaningful project context on org-wide pages.

**Requires:** `SetOrganizationFromUrl` (or equivalent) must have run first.

**Sets assigns:**
- `socket.assigns.current_scope` — enriched with `project` and `project_membership` when a preferred project is found; unchanged when none is found

**Use when:** `live_session :org_scoped` — org dashboard and org-level management pages that do not encode a project in the URL.

**Do NOT use when:** Project-scoped routes (`:project_scoped`, `:project_editor`) — the project comes from the URL there via `SetProjectFromUrl`.

**Side effects:** None. Always returns `{:cont, socket}`.

---

### `SetDefaultProject` (`hooks/set_default_project.ex`)

**Purpose:** Loads the organization's default project into `current_scope` when the scope has an org but no project. Unlike `SetPreferredProject`, it does not consult last-visited history — it queries `Projects.get_default_project/1` directly.

**Sets assigns:**
- `socket.assigns.current_scope` — enriched with `project` and `project_membership` when a default project exists; unchanged otherwise

**Use when:** Contexts where you need a project in scope but do not have last-visited history available, and you want the org's designated default rather than any user preference. Currently not wired into any `live_session` in the router — available for one-off use or future sessions.

**Do NOT use when:** Org-scoped live sessions where `SetPreferredProject` is already present (that hook subsumes this one with smarter fallback logic).

**Side effects:** None. Always returns `{:cont, socket}`.

---

### `TrackCurrentPath` (`hooks/track_current_path.ex`)

**Purpose:** Attaches a `handle_params` lifecycle hook that updates `current_path` on every navigation event. The sidebar uses `current_path` to highlight the active nav item.

**Sets assigns:**
- `socket.assigns.current_path` — initialized to `nil` on mount, then set to `URI.parse(url).path` on every `handle_params` call (including live navigations within the same session)

**Use when:** Any `live_session` whose layout contains a sidebar or navigation component that needs to know the active route. Present in all authenticated sessions: `:org_scoped`, `:project_scoped`, `:project_editor`, `:require_authenticated_user`, `:editor`.

**Do NOT use when:** `:current_user` (auth pages) and `:admin` sessions — those layouts do not use a path-sensitive sidebar.

**Side effects:** None. Always returns `{:cont, socket}`.

---

### `TrackLastVisited` (`hooks/track_last_visited.ex`)

**Purpose:** Persists the current org + project IDs as the user's last-visited workspace by calling `Accounts.touch_last_visited/3`. Runs after all scope hooks so it sees the fully resolved IDs. Writes are skipped when the scope has no org (e.g. unauthenticated or no-org state) and are internally guarded to avoid spurious DB writes when the value hasn't changed.

**Sets assigns:** None.

**Use when:** All sessions where users navigate org/project pages and you want "last visited" to be kept current: `:org_scoped`, `:project_scoped`, `:project_editor`.

**Do NOT use when:** Flat/legacy sessions (`:require_authenticated_user`, `:editor`) or admin sessions — those do not follow the org-slug URL pattern and would record stale or misleading last-visited state.

**Side effects:** Calls `Accounts.touch_last_visited/3` (DB write). Always returns `{:cont, socket}`.

---

## Composition Patterns

Hooks run in the order listed in `on_mount: [...]`. The conventions below are derived directly from `router.ex`.

### Admin routes (`/admin/...`) — `:admin`

```elixir
live_session :admin,
  layout: false,
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},  # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganization, :default},   # 2. org from session
    Backpex.InitAssigns                               # 3. Backpex internals
  ]
```

Notes: uses session-based org resolution (not URL slug); no path tracking or last-visited.

---

### Org-scoped routes (`/orgs/:org_slug/...`) — `:org_scoped`

```elixir
live_session :org_scoped,
  layout: {BlackboexWeb.Layouts, :app},
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},           # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},     # 2. org from :org_slug param
    {BlackboexWeb.Hooks.SetPreferredProject, :default},        # 3. best-guess project (last-visited or default)
    {BlackboexWeb.Hooks.TrackCurrentPath, :default},           # 4. sidebar active state
    {BlackboexWeb.Hooks.TrackLastVisited, :default}            # 5. persist last-visited workspace
  ]
```

Routes: org dashboard, billing, settings, members, project list.

---

### Project-scoped routes (`/orgs/:org_slug/projects/:project_slug/...`) — `:project_scoped`

```elixir
live_session :project_scoped,
  layout: {BlackboexWeb.Layouts, :app},
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},           # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},     # 2. org from :org_slug param
    {BlackboexWeb.Hooks.SetProjectFromUrl, :default},          # 3. project from :project_slug param
    {BlackboexWeb.Hooks.TrackCurrentPath, :default},           # 4. sidebar active state
    {BlackboexWeb.Hooks.TrackLastVisited, :default}            # 5. persist last-visited workspace
  ]
```

Routes: project dashboard, APIs, flows, pages, playgrounds, API keys, members, settings.

---

### Project editor routes (`/orgs/:org_slug/projects/:project_slug/.../edit`) — `:project_editor`

```elixir
live_session :project_editor,
  layout: {BlackboexWeb.Layouts, :editor},
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},           # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganizationFromUrl, :default},     # 2. org from :org_slug param
    {BlackboexWeb.Hooks.SetProjectFromUrl, :default},          # 3. project from :project_slug param
    {BlackboexWeb.Hooks.TrackCurrentPath, :default},           # 4. sidebar active state
    {BlackboexWeb.Hooks.TrackLastVisited, :default}            # 5. persist last-visited workspace
  ]
```

Routes: API editor tabs, page editor, playground editor, flow editor.

Note: identical hook chain to `:project_scoped`; differs only in layout (`editor` vs `app`).

---

### Legacy flat authenticated routes (`/apis`, `/flows`, etc.) — `:require_authenticated_user`

```elixir
live_session :require_authenticated_user,
  layout: {BlackboexWeb.Layouts, :app},
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},   # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganization, :default},    # 2. org from session (no URL slug)
    {BlackboexWeb.Hooks.TrackCurrentPath, :default}    # 3. sidebar active state
  ]
```

No `TrackLastVisited` — these routes predate the org-slug URL scheme.

---

### Legacy flat editor routes — `:editor`

```elixir
live_session :editor,
  layout: {BlackboexWeb.Layouts, :editor},
  on_mount: [
    {BlackboexWeb.UserAuth, :require_authenticated},   # 1. auth gate
    {BlackboexWeb.Hooks.SetOrganization, :default},    # 2. org from session
    {BlackboexWeb.Hooks.TrackCurrentPath, :default}    # 3. sidebar active state
  ]
```

---

### Public auth routes (`/users/log-in`, `/invitations/:token`) — `:current_user`

```elixir
live_session :current_user,
  layout: {BlackboexWeb.Layouts, :auth},
  on_mount: [{BlackboexWeb.UserAuth, :mount_current_scope}]
```

Only mounts the scope (user may be nil); no org, no path tracking.

---

## Dependency Order Rules

When composing hooks for a new `live_session`, respect this ordering:

1. `{BlackboexWeb.UserAuth, :require_authenticated}` — always first; gates everything else
2. Scope resolution (org then project):
   - URL-based: `SetOrganizationFromUrl` → `SetProjectFromUrl`
   - Session-based: `SetOrganization` (no project hook needed for flat routes)
   - Org-only with project hint: `SetOrganizationFromUrl` → `SetPreferredProject`
3. `TrackCurrentPath` — after scope is set (reads nothing from scope, but logically belongs after context is established)
4. `TrackLastVisited` — always last; depends on fully resolved scope to write correct IDs
