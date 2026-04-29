# AGENTS.md — Audit Context

Row-level change tracking and operation-level audit logging. Facade: `Blackboex.Audit` (`audit.ex`).

## Query Module

`AuditQueries` — all `Ecto.Query` composition for audit logs and version history. Sub-modules call `AuditQueries`, not inline queries.

## Two Mechanisms

| Mechanism | Storage | When |
|-----------|---------|------|
| ExAudit row-level | `versions` table | Automatic on tracked schema insert/update/delete |
| `Audit.log/2` | `audit_logs` table | Explicit business events (published, revoked, etc.) |

## Tracked Schemas (config/config.exs)

`Apis.Api`, `Apis.ApiKey`, `Organizations.Organization`

To add: append to `tracked_schemas` list in config. No other code changes needed.

## Public API

```elixir
Audit.log(action, attrs) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
Audit.track(keyword()) :: :ok          # thin wrapper over ExAudit.track/1
Audit.list_logs(org_id, opts \\ []) :: [AuditLog.t()]
Audit.list_recent_activity(org_id, limit \\ 10) :: [map()]
Audit.list_user_logs(user_id, opts \\ []) :: [AuditLog.t()]
```

`Audit.log/2` usage:
```elixir
Audit.log("api.published", %{
  user_id: scope.user.id,
  organization_id: scope.organization.id,
  resource_type: "Api",
  resource_id: api.id,
  metadata: %{name: api.name}
})
```

## AuditLog Schema

Table `audit_logs`. Fields: `action` (required, dotted verb), `resource_type`, `resource_id`, `metadata` (jsonb), `ip_address`, `user_id` (integer FK), `organization_id` (uuid FK). No `updated_at` — immutable.

## AuditContext Plug

`BlackboexWeb.Plugs.AuditContext` sets ExAudit process-level tracking (actor_id, ip_address) on every authenticated request. Applied to all LiveView and admin pipelines.

**Rule:** Never call `ExAudit.track/1` from `blackboex_web` — always use `Blackboex.Audit.track/1`.

## Gotchas

1. **Audit logs are immutable** — never add edit/create routes in admin panel.
2. **`actor_id` is integer FK** — matches `users.id` (serial integer), not UUID. Don't change to `:binary_id`.
3. **Ordering flakiness in tests** — assert on set membership, not positional order (same `inserted_at` possible).
4. **Drop `:audit_context` from pipeline** → versions created without `actor_id` (non-attributable).
5. **`metadata` should be bounded** — avoid full structs or large blobs; JSONB bloat attack vector.
