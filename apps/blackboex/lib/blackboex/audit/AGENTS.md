# Audit Context — AGENTS.md

Row-level change tracking and operation-level audit logging for Blackboex.

## Overview

The Audit context provides two complementary audit mechanisms:

1. **ExAudit row-level versioning** — automatic structural diffs captured on every `insert`, `update`, and `delete` for configured schemas. Stored in the `versions` table. No application code required at call sites beyond wiring the Repo.

2. **Operation-level AuditLog** — explicit business events written manually via `Audit.log/2`. Stored in the `audit_logs` table. Used for semantic actions like `"api.published"` or `"api_key.revoked"` that carry business meaning beyond a raw field diff.

Both mechanisms record the actor (`user_id` / `actor_id`) and `ip_address` injected at the HTTP layer via `BlackboexWeb.Plugs.AuditContext`.

The domain facade is `Blackboex.Audit`. Web code MUST call it rather than calling `ExAudit` directly — the domain app owns the ExAudit dependency and calling it from `blackboex_web` produces compile-time warnings (cross-app dep visibility).

## Tracked Schemas

Configured in `config/config.exs` under `:ex_audit`:

| Schema | Table | Reason |
|---|---|---|
| `Blackboex.Billing.Subscription` | `subscriptions` | Plan changes are high-value billing events |
| `Blackboex.Apis.Api` | `apis` | API lifecycle changes (publish, archive) |
| `Blackboex.Apis.ApiKey` | `api_keys` | Key creation/revocation security events |
| `Blackboex.Organizations.Organization` | `organizations` | Org-level settings and ownership changes |

ExAudit automatically intercepts `Repo.insert/2`, `Repo.update/2`, and `Repo.delete/2` calls on these schemas. No per-call opt-in needed.

## AuditLog Schema

`Blackboex.Audit.AuditLog` — table `audit_logs`.

| Field | Type | Notes |
|---|---|---|
| `id` | `binary_id` | UUID primary key |
| `action` | `string` | Required. Dotted verb format: `"api.published"`, `"api_key.revoked"` |
| `resource_type` | `string` | Optional. Human-readable resource name |
| `resource_id` | `string` | Optional. External-facing ID of the affected resource |
| `metadata` | `map` | Optional JSONB blob. Defaults to `%{}`. Keep keys bounded — JSONB bloat attack vector |
| `ip_address` | `string` | Max 45 chars (supports IPv6). Injected by AuditContext plug |
| `user_id` | `integer` | FK to `users`. Integer PK (not UUID) |
| `organization_id` | `binary_id` | FK to `organizations` |
| `inserted_at` | `utc_datetime` | No `updated_at` — logs are immutable |

Constraints: `action` required, max 255 chars. `resource_type` and `resource_id` max 255. `ip_address` max 45. `user_id` and `organization_id` have FK constraints with no cascade delete (logs survive user/org deletion).

Audit logs are **immutable**. `admin_changeset/3` delegates to the regular changeset but Backpex is configured read-only — never add edit/create routes for this resource.

### Manual Logging via Audit.log/2

```elixir
# In a domain context after a successful operation:
Audit.log("api.published", %{
  user_id: scope.user.id,
  organization_id: scope.organization.id,
  resource_type: "Api",
  resource_id: api.id,
  metadata: %{name: api.name}
})
```

Existing call sites: `Billing` (subscription.updated), `Organizations` (member.added), `Apis` (api.published, api.unpublished), `Apis.Keys` (api_key.created, api_key.revoked).

## Version Schema

`Blackboex.Audit.Version` — table `versions`. Managed by ExAudit automatically.

| Field | Type | Notes |
|---|---|---|
| `id` | `integer` | Auto-increment primary key (no UUID) |
| `patch` | `ExAudit.Type.Patch` | Binary-encoded diff of changed fields |
| `entity_id` | `binary_id` | UUID of the changed record |
| `entity_schema` | `ExAudit.Type.Schema` | Full module name, e.g. `Blackboex.Apis.Api` |
| `action` | `ExAudit.Type.Action` | `:insert`, `:update`, or `:delete` |
| `recorded_at` | `utc_datetime_usec` | Microsecond precision timestamp |
| `rollback` | `boolean` | True when this version was created by a rollback operation |
| `actor_id` | `integer` | FK to `users` (nilify_all on user deletion) |
| `ip_address` | `string` | Propagated from ExAudit process-level tracking |

Indexes: `(entity_id, entity_schema)` for per-record history lookups; `(actor_id)` for per-user change history.

The `patch` field stores a structural diff (not a full snapshot). Use `ExAudit.Schema` helpers or inspect via the admin panel's version detail view which renders `patch` with `inspect/2`.

## AuditContext Plug

`BlackboexWeb.Plugs.AuditContext` — sets ExAudit process-level tracking data so every `Repo` call within the request carries actor metadata.

```elixir
def call(conn, _opts) do
  scope = conn.assigns[:current_scope]

  if scope && scope.user do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    Blackboex.Audit.track(actor_id: scope.user.id, ip_address: ip)
  end

  conn
end
```

`Blackboex.Audit.track/1` is a thin wrapper over `ExAudit.track/1` that keeps the ExAudit dep inside the domain app.

### Where it is applied

The plug is declared as a pipeline in the router:

```elixir
pipeline :audit_context do
  plug BlackboexWeb.Plugs.AuditContext
end
```

Applied to two scopes:

- **Authenticated user scope** (`pipe_through [:browser, :require_authenticated_user, :audit_context]`) — all LiveViews under `/dashboard`, `/apis`, `/api-keys`, `/billing`, `/settings`.
- **Admin scope** (`pipe_through [:browser, :admin_layout, :require_authenticated_user, :require_platform_admin, :audit_context]`) — all Backpex resources under `/admin`.

The plug runs after `fetch_current_scope_for_user`, so `conn.assigns[:current_scope]` is guaranteed to be populated. If `current_scope` or `scope.user` is nil (unauthenticated request that somehow reaches this plug), it is a no-op.

## How to Add Tracking to a New Schema

### ExAudit Row-Level Tracking

1. Add the schema module to `tracked_schemas` in `config/config.exs`:

```elixir
config :ex_audit,
  ecto_repos: [Blackboex.Repo],
  version_schema: Blackboex.Audit.Version,
  tracked_schemas: [
    Blackboex.Billing.Subscription,
    Blackboex.Apis.Api,
    Blackboex.Apis.ApiKey,
    Blackboex.Organizations.Organization,
    Blackboex.YourContext.YourSchema  # add here
  ]
```

2. No changes to the schema module or Repo calls are needed. ExAudit intercepts at the Repo level via `use ExAudit.Repo` in `Blackboex.Repo`.

3. Verify with a test: after inserting/updating a record, assert a `Version` row exists with `entity_schema: Blackboex.YourContext.YourSchema`.

### Operation-Level AuditLog

Call `Blackboex.Audit.log/2` inside the domain context function after a successful operation:

```elixir
def your_operation(scope, attrs) do
  with {:ok, record} <- Repo.insert(changeset) do
    Audit.log("resource.action", %{
      user_id: scope.user.id,
      organization_id: scope.organization.id,
      resource_type: "YourSchema",
      resource_id: record.id,
      metadata: %{relevant: "fields"}
    })

    {:ok, record}
  end
end
```

Keep `metadata` bounded — use only fields necessary for human audit review. Avoid putting full structs or large blobs in metadata.

## Query Patterns

All query functions are on the `Blackboex.Audit` facade.

```elixir
# Recent activity for an org (formatted map list, limit 10)
Audit.list_recent_activity(org_id)
Audit.list_recent_activity(org_id, 25)

# Raw AuditLog records for an org
Audit.list_logs(organization_id)
Audit.list_logs(organization_id, limit: 100)

# Raw AuditLog records for a user (used in SettingsLive)
Audit.list_user_logs(user_id)
Audit.list_user_logs(user_id, limit: 20)
```

All queries order by `inserted_at DESC` and default to `limit: 50`.

For ExAudit version history on a specific record, use ExAudit's built-in helpers or query `Version` directly:

```elixir
import Ecto.Query

Blackboex.Repo.all(
  from v in Blackboex.Audit.Version,
    where: v.entity_id == ^record_id and v.entity_schema == ^Blackboex.Apis.Api,
    order_by: [desc: v.recorded_at]
)
```

The admin panel surfaces both tables at `/admin/audit-logs` and `/admin/versions`.

## Gotchas

### Audit trail gaps in admin scope

If `:audit_context` is dropped from the admin pipeline, all Backpex mutations (editing a user, changing a subscription) execute without `actor_id` or `ip_address` on the resulting `Version` records. The ExAudit version row is still created (because the schema is tracked), but `actor_id` will be `nil` — making the trail non-attributable. Always verify `:audit_context` is in every authenticated pipeline.

### AuditLog is immutable — do not add edit/create routes

`AuditLog.admin_changeset/3` exists only because Backpex requires it, but audit logs must not be writable from the admin panel. The Backpex resource is intentionally configured to allow all actions in `can?/3` but the records should be treated as append-only. If a future refactor adds `only: [:index, :show]` to the Backpex route, do not remove it.

### Ordering flakiness in tests

Tests that sort audit records by `inserted_at` can be flaky when multiple records are created in the same test — Postgres timestamps can resolve to the same second. Assert on set membership (`action in actions`) rather than positional order.

### ExAudit patch is a binary diff, not a snapshot

The `versions.patch` field stores only the diff between old and new state, not a full snapshot. To reconstruct state at a point in time, you must replay the patch chain from the original insert. Use ExAudit's rollback APIs cautiously — they create new `Version` rows with `rollback: true` rather than deleting existing ones.

### Cross-app dep visibility

Never call `ExAudit.track/1` directly from `blackboex_web`. The `blackboex_web` app does not list `ex_audit` as a direct dependency, so the compiler will warn (and fail with `--warnings-as-errors`). Always go through `Blackboex.Audit.track/1`.

### actor_id uses integer FK, not UUID

`versions.actor_id` is an integer FK to `users` (matching `users.id` which is a serial integer), while most other FKs in the system are `binary_id` UUIDs. This asymmetry is intentional — ExAudit requires the actor FK to match the user PK type. Do not change `actor_id` to `:binary_id` in the Version schema.
