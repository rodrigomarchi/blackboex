# AGENTS.md — Apis Context

Facade: `Blackboex.Apis` (`apis.ex`). All web/worker code calls through this facade. Direct sub-module access is forbidden.

## Sub-Contexts

| Module | Purpose | File |
|--------|---------|------|
| `Apis.Files` | File CRUD, upsert, snapshots | `apis/files.ex` |
| `Apis.Versions` | Version creation, rollback, listing | `apis/versions.ex` |
| `Apis.Lifecycle` | publish, unpublish, deploy | `apis/lifecycle.ex` |
| `Apis.Templates` | `create_api_from_template/3`, template listing | `apis/templates.ex` |
| `Apis.Keys` | API key issuance, verification, revocation | `apis/keys.ex` |
| `Apis.Analytics` | Invocation metrics, dashboard queries | `apis/analytics.ex` |

## Query Modules

| Module | Scope | File |
|--------|-------|------|
| `Apis.ApiQueries` | Api record lookups, list, search | `apis/api_queries.ex` |
| `Apis.FileQueries` | File lookups by api/path/type | `apis/file_queries.ex` |
| `Apis.VersionQueries` | Version lookups, latest, rollback | `apis/version_queries.ex` |

**Rule:** All `Ecto.Query` composition lives in `*Queries` modules. Sub-contexts call queries, not inline `from` expressions.

## Sub-Context Dependencies

```
Lifecycle  ──→ ApiQueries, Apis.Registry, CodeGen.Compiler, Audit
Versions   ──→ VersionQueries, FileQueries (snapshots)
Files      ──→ FileQueries
Keys       ──→ Audit
Analytics  ──→ ApiQueries, Apis.DashboardQueries
Templates  ──→ ApiQueries, Files
```

## Lifecycle State Machine

```
draft ──→ compiled ──→ published ──→ compiled  (unpublish)
```

`generation_status` is orthogonal: `generating | complete | error`. Set by `Agent` context, not `Apis`.

**No PubSub in Apis context.** PubSub is driven by `Agent.Session` on `"run:#{run_id}"`.

## Key Schemas

| Schema | Table | Notes |
|--------|-------|-------|
| `Api` | `apis` | Core entity. slug auto-generated from name. |
| `ApiKey` | `api_keys` | SHA-256 hash only. Plain key returned once. |
| `ApiVersion` | `api_versions` | Immutable. `file_snapshots` jsonb. |
| `ApiFile` | `api_files` | Virtual filesystem per API |
| `ApiFileRevision` | `api_file_revisions` | Append-only revision history |
| `InvocationLog` | `invocation_logs` | Append-only. No `updated_at`. |
| `MetricRollup` | `api_metric_rollups` | Unique `(api_id, date, hour)` |
| `DataStore.Entry` | `api_data` | KV store. Unique `(api_id, key)`. Upsert. |

## Public API (Facade)

```elixir
# Core CRUD
create_api(map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()} | {:error, :limit_exceeded, map()}
list_apis(org_id) :: [Api.t()]
list_apis_for_project(project_id) :: [Api.t()]                        # ordered by inserted_at DESC
list_for_project(project_id, opts \\ []) :: [Api.t()]                 # ordered by name ASC; accepts :limit (default 50)
get_api(org_id, api_id) :: Api.t() | nil    # ALWAYS both args — bare id is IDOR
get_for_org(org_id, api_id) :: Api.t() | nil  # org-scoped fetch by id; returns nil when not found or cross-org
update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
move_api(Api.t(), new_project_id) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}  # moves API to a different project within the same org; validates ownership via ensure_project_in_org
delete_api(Api.t()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}

# Lifecycle (delegated to Apis.Lifecycle)
publish(Api.t(), Organization.t()) :: {:ok, Api.t()} | {:error, :not_compiled | :org_mismatch | ...}
unpublish(Api.t()) :: {:ok, Api.t()} | {:error, :not_published | ...}

# Versions (delegated to Apis.Versions)
create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
list_versions(api_id) :: [ApiVersion.t()]
rollback_to_version(Api.t(), version_number, created_by_id) :: {:ok, ApiVersion.t()} | {:error, ...}

# Files (delegated to Apis.Files)
list_files(Api.t()) :: [ApiFile.t()]
get_file(Api.t(), path) :: ApiFile.t() | nil
create_file(Api.t(), map()) :: {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
update_file_content(ApiFile.t(), content, user_id) :: {:ok, ApiFile.t()} | {:error, ...}
upsert_files(Api.t(), [map()], user_id) :: {:ok, [ApiFile.t()]} | {:error, ...}

# Templates (delegated to Apis.Templates)
create_api_from_template(template_type, org_id, user_id) :: {:ok, Api.t()} | {:error, ...}
```

**Removed from facade:** `start_agent_generation/3`, `start_agent_edit/3` — now in `Blackboex.Agent`.

## Key Modules (Non-Sub-Context)

### `Apis.Registry`
GenServer. ETS-backed O(1) lookups. `lookup/1` and `lookup_by_path/2` bypass GenServer (direct ETS reads). Writes go through `GenServer.call`. Recompiles all published APIs on startup from `source_code`.

### `Apis.Deployer`
Zero-downtime hot-reload: `compile → smoke_test → register`. `rollback_deploy/3` recompiles from a version snapshot.

### `Apis.DashboardQueries`
Org-level aggregated queries. `get_org_summary/1`, `list_apis_with_stats/2`, `search_apis/2`, `get_dashboard_metrics/2`.

## Invariants — Never Violate

1. `get_api(org_id, api_id)` — both args required. Bare `api_id` is IDOR.
2. `create_api` always goes through `create_api_with_lock/2` (advisory lock).
3. Version numbering inside `Ecto.Multi` only.
4. `publish/2` pattern-matches `status: "compiled"`.
5. Order on delete: `Registry.unregister/1` → `Compiler.unload/1` → DB delete.
6. Plain API key returned once. Never log, store, or put in a changeset field.
7. `InvocationLog` is append-only. Never `Repo.update` a log record.

## Testing

```elixir
setup :create_org_and_api  # use named setup, not inline

# IDOR regression: always assert
assert Apis.get_api(other_org.id, api.id) == nil
```

Tag publish/unpublish tests with `@tag :capture_log` — Registry operations log.
