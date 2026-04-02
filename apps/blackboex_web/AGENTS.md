# AGENTS.md — Web App (blackboex_web)

Phoenix web layer. LiveViews, admin panel, dynamic API routing, components.

## Routing Map

### Public (no auth)
- `GET /` → PageController.home
- `GET /p/:org_slug/:api_slug` → PublicApiController.show (public API docs + Swagger UI)
- `POST /webhooks/stripe` → WebhookController (signature verified)

### Dynamic API Routing
- `POST|GET /api/*` → forward to `DynamicApiRouter`
  - Pipeline: ApiAuth → RateLimiter → Billing.Enforcement → Sandbox execution
  - On-demand compilation from DB if not in Registry

### Authenticated User Routes
- `GET /dashboard` → DashboardLive
- `GET /apis` → ApiLive.Index
- `GET /apis/new` → ApiLive.New
- `GET /apis/:id` → ApiLive.Show
- `GET /apis/:id/edit` → ApiLive.Edit (separate live_session with editor layout)
- `GET /apis/:id/analytics` → ApiLive.Analytics
- `GET /api-keys` → ApiKeyLive.Index
- `GET /billing` → BillingLive.Plans
- `GET /billing/manage` → BillingLive.Manage
- `GET /settings` → SettingsLive

### Admin Panel (platform admins only)
- Scope `/admin` — 23 Backpex resources
- All require `is_platform_admin == true`
- Full CRUD on all system tables

### Auth Routes
- `GET /users/register`, `GET /users/log-in`, `GET /users/log-in/:token`
- `POST /users/log-in`, `DELETE /users/log-out`

## Auth Flow

```
Login → UserSessionController.create
  → generate_user_session_token → store in session + optional remember-me (14d)
  → per-request: UserAuth.fetch_current_scope_for_user plug
  → builds Scope = %{user, organization, membership}
  → LiveView: on_mount :mount_current_scope, :require_authenticated
  → SetOrganization hook loads org from session (falls back to first org)
  → Token reissue every 7 days
```

## Pipelines & Plugs

| Plug | Purpose |
|------|---------|
| `UserAuth` | Session/token management, on_mount hooks |
| `SetOrganization` | Loads org from session, sets `current_scope.organization` |
| `DynamicApiRouter` | Resolves compiled module, executes in sandbox |
| `ApiAuth` | Bearer token / X-Api-Key / query param verification |
| `RateLimiter` | 4-layer: per-IP (100/min), per-key (60/min), per-API (1000/min), per-endpoint |
| `AuditContext` | Injects user_id + IP into ExAudit process tracking |
| `RequirePlatformAdmin` | Gates `/admin` scope |
| `CacheBodyReader` | Caches raw body for auth + execution |

## Rate Limiting

4 layers, all enforced in `DynamicApiRouter`:
1. **Per-IP:** 100 req/min (via remote IP)
2. **Per-API-Key:** 60 req/min (configurable per key in DB)
3. **Per-API (global):** 1000 req/min across all keys
4. **Per-endpoint:** Computed from API config

Backend: `RateLimiterBackend` (ETS-based GenServer, cleanup every 10 min)

## LiveView Patterns

### Thin LiveViews
All business logic MUST be in domain contexts. LiveViews only:
- Mount: load data via context facade
- Handle events: call context function, update assigns
- Handle info: receive PubSub/Task results, update assigns

### Async Work
```elixir
# CORRECT — non-blocking
task = Task.async(fn -> heavy_work() end)
socket = assign(socket, loading: true, task_ref: task.ref)

# handle_info({ref, result}, socket) — success
# handle_info({:DOWN, ref, ...}, socket) — crash

# WRONG — blocks LiveView process
send(self(), :do_heavy_work)
```

### PubSub Subscriptions
```elixir
# Subscribe in mount
Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")
Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

# Receive in handle_info
def handle_info({:event_appended, event}, socket), do: ...
def handle_info({:run_completed, run}, socket), do: ...
```

## Components

| Component | Purpose |
|-----------|---------|
| `CoreComponents` | Flash, button, input, header, table, list, icon |
| `ChatPanel` | Agent conversation UI in editor |
| `RequestBuilder` | Live form for API testing (params/headers/body/auth) |
| `ResponseViewer` | API response display with syntax highlighting |
| `EditorToolbar` | Compile, publish, test, docs buttons |
| `CommandPalette` | Keyboard-driven command launcher |
| `PipelineStatus` | Compilation pipeline stage indicator |
| `Charts` | Server-side SVG charts (zero JS) |

**Base:** SaladUI components + TwMerge for Tailwind class merging + Heroicons

## Layouts

| Layout | Used By |
|--------|---------|
| `app` | Dashboard, APIs list, billing, settings |
| `auth` | Login, register (centered card, minimal chrome) |
| `editor` | API editor (full-height, no chrome, editor manages toolbar) |
| `admin` | Backpex admin panel |

## Admin Panel (Backpex)

- 23 LiveResource modules at `/admin/`
- Pattern: `use Backpex.LiveResource` with schema + repo + changeset config
- Authorization: `can?/3` checks `current_scope.user.is_platform_admin`
- Admin changesets MUST be arity 3: `admin_changeset/3` (with `_metadata`)
- Admin changesets MUST restrict editable fields (don't reuse regular changeset)
- Audit logs are read-only: `only: [:index, :show]`

## Gotchas

1. **Monaco Editor** — doesn't react to `value` assign changes. Use `LiveMonacoEditor.set_value/3`.
2. **`@module_attr` in HEEx** — resolves to assigns, NOT module attributes. Hardcode or pass as assign.
3. **handle_event clause grouping** — keep all clauses of same name/arity adjacent. Don't interleave defp.
4. **LiveComponent assigns** — not inherited from parent. Pass every required assign explicitly.
5. **Esbuild umbrella imports** — use NODE_PATH, not relative paths like `../../deps/`.
6. **SetOrganization hook order** — must run AFTER `:mount_current_scope`. Check on_mount order in live_session.
7. **Backpex can? defensive match** — `current_scope` may not exist if hook order wrong.
