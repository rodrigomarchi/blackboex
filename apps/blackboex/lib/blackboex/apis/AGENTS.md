# AGENTS.md — Apis Context

Authoritative reference for `Blackboex.Apis` and `Blackboex.Apis.*` submodules. Read before touching any file in this directory.

---

## 1. Overview

`Blackboex.Apis` is the core business domain. It owns:

- API endpoint lifecycle (draft → compiled → published → archived)
- Versioning and diff tracking of generated source code
- Runtime deployment: compiling Elixir modules, ETS registry, HTTP routing
- API key issuance, hashing, verification, and revocation
- Invocation logging and metric aggregation
- Key-value DataStore for deployed CRUD APIs
- Dashboard and analytics queries scoped to an organization

Facade: `Blackboex.Apis` (`apis.ex`). All LiveView and web-layer code must call through this facade. Direct submodule access from web code is forbidden.

---

## 2. Lifecycle State Machine

### Valid States

| State       | Meaning                                                     |
|-------------|-------------------------------------------------------------|
| `draft`     | Newly created, no valid compiled code yet                   |
| `compiled`  | Source code validated/compiled by `CodeGen`                 |
| `published` | Live — Plug module loaded and routed by `Registry`         |
| `archived`  | Retired — not callable, kept for history (manual only)      |

### Valid Transitions

```
draft ──→ compiled ──→ published ──→ compiled  (unpublish)
  ↑            |
  └────────────┘  (re-edit drops back to draft via generation_status)
```

No direct `draft → published` path. `archived` is terminal with no return path.

### Transition Triggers and Side Effects

| Transition              | Triggered by                          | Side Effects                                                                 |
|-------------------------|---------------------------------------|------------------------------------------------------------------------------|
| `draft → compiled`      | `Agent.Session` or `CodeGen` pipeline | Sets `source_code`, `test_code`, `validation_report` on `Api`               |
| `compiled → published`  | `Apis.publish/2`                      | `Registry.register/3`, async audit log `"api.published"`                    |
| `published → compiled`  | `Apis.unpublish/1`                    | `Registry.unregister/1`, `Compiler.unload/1`, async audit log               |
| any → deleted           | `Apis.delete_api/1`                   | If published: `Registry.unregister/1` + `Compiler.unload/1` first           |

`generation_status` is orthogonal to `status`: set to `"generating"` by `start_agent_generation/3`, updated to `"complete"` or `"error"` by `Agent.Session`. Does not affect routing or the state machine.

**No PubSub broadcasts happen in the `Apis` context itself.** PubSub is driven by `Agent.Session` on `"run:#{run_id}"`.

---

## 3. Key Modules

### `Blackboex.Apis.Api`

Schema for the core entity. Table: `apis`. `changeset/2` validates name (required, max 200), auto-generates slug from name when absent, validates slug format (`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, max 100), enforces `unique_constraint([:organization_id, :slug])`, validates JSON size on `param_schema`, `example_request`, `example_response`. `admin_changeset/3` delegates to `changeset/2`. Associations: `belongs_to :organization`, `belongs_to :user` (integer FK), `has_one :conversation`.

### `Blackboex.Apis.ApiKey`

Keys are never stored in plain text. Only SHA-256 binary hash (`key_hash`) and display prefix (`key_prefix`, first 16 chars) are stored. `rate_limit` optional integer > 0. `expires_at` / `revoked_at` nullable UTC timestamps. `last_used_at` debounced to at most once per 60 seconds.

### `Blackboex.Apis.ApiVersion`

Immutable snapshot on every save/generation/rollback. `version_number` monotonically increasing per `api_id`, computed in a transaction via `MAX + 1`. `source` ∈ `generation | manual_edit | chat_edit | rollback`. `compilation_status` ∈ `pending | success | error`. `diff_summary` produced by `DiffEngine.format_diff_summary/1`. Unique: `[:api_id, :version_number]`.

### `Blackboex.Apis.Analytics`

Per-API invocation metrics. `log_invocation/1` is fire-and-forget (async via `LoggingSupervisor`, always returns `:ok`). Other functions accept `(api_id, opts)` with `period: :all | :day | :week | :month`: `invocations_count/2`, `success_rate/2`, `avg_latency/2`, `error_count/2`, `recent_errors/2`.

### `Blackboex.Apis.DashboardQueries`

Org-level aggregated queries. All functions scope to `organization_id`. LIKE injection prevented via `sanitize_like/1`.

| Function                 | Returns                                                                  |
|--------------------------|--------------------------------------------------------------------------|
| `get_org_summary/1`      | `%{total_apis, calls_today, errors_today, avg_latency_today}`           |
| `list_apis_with_stats/2` | `[%{api, calls_24h, errors_24h, avg_latency}]`                          |
| `search_apis/2`          | `[Api.t()]` — ILIKE on name and description                             |
| `get_dashboard_metrics/2`| Series maps + top_apis (uses MetricRollup); period: `"24h"/"7d"/"30d"` |
| `get_llm_usage_series/2` | Generations series + token/cost totals (uses `DailyUsage`)              |

Period semantics: `"24h"` = today's hourly data (not rolling). `"7d"/"30d"` = daily. Gap-filling ensures every bucket has an entry.

### `Blackboex.Apis.DataStore` / `Blackboex.Apis.DataStore.Entry`

Key-value store for deployed CRUD APIs. Table: `api_data`. Scoped strictly to `api_id`. `put/3` upserts via `on_conflict`. `value` is JSONB. Unique: `[:api_id, :key]`.

### `Blackboex.Apis.Deployer`

Zero-downtime hot-reload of published APIs.

**`deploy/2`:** (1) `Compiler.compile/2`, (2) `smoke_test/2` — calls `module.init([])` + `module.call(conn, opts)` with `example_request`, requires 2xx, (3) `Registry.register/3`. Does not change `status`.

**`rollback_deploy/3`:** `rollback_to_version/3` → recompile → re-register.

### `Blackboex.Apis.DiffEngine`

- `compute_diff/2` — `List.myers_difference/2` on lines
- `format_diff_summary/1` — `"N added, M removed"` string
- `apply_search_replace/2` — applies `[%{search, replace}]` sequentially; exact match first, falls back to whitespace-normalized fuzzy; returns `{:error, :search_not_found, search_text}` on failure

### `Blackboex.Apis.InvocationLog`

Immutable append-only. Table: `invocation_logs`. Uses `timestamps(updated_at: false)` — no `updated_at`. Fields: `api_id`, `api_key_id`, `method`, `path` (max 2048), `status_code` (100–599), `duration_ms`, `request_body_size`, `response_body_size`, `ip_address` (max 45, IPv6), `error_message`. Never update a record.

### `Blackboex.Apis.Keys`

Format: `bb_live_` prefix + 32 lowercase hex chars = 40 chars total. Prefix stored = first 16 chars.

| Function              | Returns                                                    | Notes                                                  |
|-----------------------|------------------------------------------------------------|--------------------------------------------------------|
| `create_key/2`        | `{:ok, plain_key, ApiKey.t()} \| {:error, cs}`            | Plain key returned ONCE. Async audit log.              |
| `verify_key/1`        | `{:ok, ApiKey.t()} \| {:error, :invalid/:revoked/:expired}` | Always calls `secure_compare`, even for unknown keys  |
| `verify_key_for_api/2`| Same + checks `api_key.api_id == api_id`                  |                                                        |
| `revoke_key/1`        | `{:ok, ApiKey.t()} \| {:error, cs}`                        | Sets `revoked_at`. Async audit log.                    |
| `rotate_key/1`        | `{:ok, plain_key, ApiKey.t()} \| {:error, cs}`             | Atomic: revoke old + create new in `Ecto.Multi`        |
| `touch_last_used/1`   | `:ok`                                                      | Debounced: skips if `last_used_at` < 60s ago           |
| `key_metrics/2`       | `%{total_requests, errors, avg_latency, success_rate}`    | Period: `:day \| :week \| :month`                      |

### `Blackboex.Apis.MetricRollup` / `Blackboex.Apis.MetricRollupWorker`

Schema: `api_metric_rollups`. Fields: `api_id`, `date`, `hour` (0–23), `invocations`, `errors`, `avg_duration_ms`, `p95_duration_ms`, `unique_consumers`. Unique: `[:api_id, :date, :hour]`.

Worker (Oban, queue `:analytics`, cron hourly): aggregates previous hour's `invocation_logs`, computes p95 via PostgreSQL `percentile_cont`, upserts idempotently. Accepts `%{"date", "hour"}` args for backfill.

### `Blackboex.Apis.Registry`

GenServer owning two ETS tables for O(1) lookups.

| ETS Table              | Key                      | Value                                              |
|------------------------|--------------------------|----------------------------------------------------|
| `:api_registry`        | `api_id` (UUID string)   | `{module_atom, %{requires_auth, visibility, api_id}}` |
| `:api_registry_paths`  | `{org_slug, api_slug}`   | `api_id`                                           |

Both tables `:public` with `read_concurrency: true`. Lookups (`lookup/1`, `lookup_by_path/2`) bypass GenServer — direct ETS reads. Writes (`register/3`, `unregister/1`, `clear/0`) go through `GenServer.call`.

On startup: `init/1` synchronously recompiles all `compiled`/`published` APIs from `source_code`. If `source_code` is nil, the API is skipped with a warning.

Graceful shutdown: sets `:persistent_term` flag, drains `SandboxTaskSupervisor` (up to 30s), purges loaded modules, clears ETS.

---

## 4. Public API (Facade: `Blackboex.Apis`)

```elixir
create_api(map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()} | {:error, :limit_exceeded, map()}
```
Requires `organization_id` to trigger advisory lock + billing enforcement. Lock key: `:erlang.phash2({"create_api", org_id})`.

```elixir
list_apis(org_id) :: [Api.t()]                        # ordered desc inserted_at
get_api(org_id, api_id) :: Api.t() | nil              # ALWAYS both args — IDOR if bare id
update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
delete_api(Api.t()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
```

```elixir
create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
list_versions(api_id) :: [ApiVersion.t()]
get_version(api_id, version_number) :: ApiVersion.t() | nil
get_latest_version(Api.t()) :: ApiVersion.t() | nil
rollback_to_version(Api.t(), version_number, created_by_id) :: {:ok, ApiVersion.t()} | {:error, :version_not_found | Ecto.Changeset.t()}
create_api_from_generation(GenerationResult.t(), org_id, user_id, trigger_message) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
```

```elixir
publish(Api.t(), Organization.t()) :: {:ok, Api.t()} | {:error, :not_compiled | :org_mismatch | Ecto.Changeset.t()}
unpublish(Api.t()) :: {:ok, Api.t()} | {:error, :not_published | Ecto.Changeset.t()}
```

```elixir
start_agent_generation(Api.t(), trigger_message, user_id) :: {:ok, String.t()} | {:error, term()}
start_agent_edit(Api.t(), instruction, user_id) :: {:ok, String.t()} | {:error, term()}
```

---

## 5. Database Schema

### `apis`

| Column             | Type    | Notes                                               |
|--------------------|---------|-----------------------------------------------------|
| `id`               | uuid    | PK                                                  |
| `name`             | text    | required, max 200                                   |
| `slug`             | text    | auto-generated, `unique(org_id, slug)`, max 100    |
| `description`      | text    | max 10,000                                          |
| `source_code`      | text    | nullable                                            |
| `test_code`        | text    | nullable                                            |
| `template_type`    | text    | `computation \| crud \| webhook`, default `computation` |
| `status`           | text    | `draft \| compiled \| published \| archived`        |
| `method`           | text    | `GET \| POST \| PUT \| PATCH \| DELETE`            |
| `param_schema`     | jsonb   | nullable                                            |
| `example_request`  | jsonb   | nullable, used by `Deployer.smoke_test`             |
| `example_response` | jsonb   | nullable                                            |
| `visibility`       | text    | `private \| public`, default `private`              |
| `requires_auth`    | boolean | default `false`                                     |
| `documentation_md` | text    | nullable                                            |
| `generation_status`| text    | nullable — `generating \| complete \| error`        |
| `generation_error` | text    | nullable                                            |
| `validation_report`| jsonb   | nullable                                            |
| `organization_id`  | uuid    | FK → organizations                                  |
| `user_id`          | bigint  | FK → users (integer PK, not UUID)                  |

### `api_keys`

| Column           | Type                | Notes                                          |
|------------------|---------------------|------------------------------------------------|
| `key_hash`       | binary (32 bytes)   | SHA-256, unique                                |
| `key_prefix`     | text                | First 16 chars                                 |
| `expires_at`     | utc_datetime_usec   | nullable                                       |
| `revoked_at`     | utc_datetime_usec   | nullable — soft delete                         |
| `rate_limit`     | integer             | nullable, > 0                                  |
| `api_id`         | uuid                | FK → apis (cascade delete)                     |
| `organization_id`| uuid                | FK → organizations                             |

### `api_versions`

| Column               | Type    | Notes                                        |
|----------------------|---------|----------------------------------------------|
| `version_number`     | integer | monotonic per api_id, `unique(api_id, version_number)` |
| `code`               | text    | required                                     |
| `source`             | text    | `generation \| manual_edit \| chat_edit \| rollback` |
| `compilation_status` | text    | `pending \| success \| error`                |
| `compilation_errors` | text[]  | default `[]`                                 |
| `diff_summary`       | text    | nullable on first version                    |
| `created_by_id`      | bigint  | FK → users, nullable                         |

### `invocation_logs`

See `InvocationLog` module above. No `updated_at`. Append-only.

### `api_metric_rollups`

See `MetricRollup` module above. Unique: `(api_id, date, hour)`.

### `api_data` (DataStore.Entry)

| Column  | Type  | Notes                         |
|---------|-------|-------------------------------|
| `api_id`| uuid  | FK → apis                     |
| `key`   | text  | required                      |
| `value` | jsonb | required                      |
| unique  | —     | `(api_id, key)` conflict target |

---

## 6. Integration Points

| Consumer | Functions called / topic |
|---|---|
| `Agent.KickoffWorker` | Receives `api_id`, `org_id`, `user_id`, `run_type`, `trigger_message` as Oban args |
| `Agent.Session` | `get_api/2`, `update_api/2`, `create_version/2`, `create_api_from_generation/4`, `CodeGen.Compiler`, `Registry` |
| `Agent.CodePipeline` | Uses `Api.t()` as context; `DiffEngine` for SEARCH/REPLACE patching |
| `Agent.RecoveryWorker` | Scans `generation_status: "generating"` stale runs; broadcasts failure |
| `CodeGen.Compiler` | Called by `Deployer.deploy/2`, `Registry.recompile_api/1`, `Agent.Session`; `module_name_for/1` derives BEAM atom from `Api` |
| `Billing.Enforcement` | `check_limit(org, :create_api)` inside advisory-locked `create_api_with_lock/2` |
| `Billing.DailyUsage` | Queried by `DashboardQueries.get_llm_usage_series/2` |
| `Conversations` | `Api` has `has_one :conversation`; managed by Agent layer, not Apis context |
| `Audit` | Async via `LoggingSupervisor` for `"api.published"`, `"api.unpublished"`, `"api_key.created"`, `"api_key.revoked"` |

---

## 7. Invariants — Never Violate These

1. **Org scoping on all queries.** `get_api(org_id, api_id)` — both args required. Bare `api_id` is IDOR.
2. **Advisory lock for creation.** All `create_api` calls with `organization_id` go through `create_api_with_lock/2` (acquires `pg_advisory_xact_lock` before billing check).
3. **Version numbering is transactional.** Compute inside `Ecto.Multi` only.
4. **Publish requires compiled status.** `publish/2` pattern-matches `status: "compiled"`.
5. **Publish enforces org identity.** `org.id` must match `api.organization_id` → `{:error, :org_mismatch}`.
6. **Unregister before unload before delete.** Order: `Registry.unregister/1` → `Compiler.unload/1` → DB delete.
7. **Plain API key returned once.** Never log, store, or put in a changeset field.
8. **Key verification is timing-safe.** Always `Plug.Crypto.secure_compare/2`. Even the "not found" branch must run a dummy compare.
9. **InvocationLog is append-only.** No `updated_at`; never `Repo.update`.
10. **DataStore.put is upsert.** Calling twice with same `(api_id, key)` overwrites — intentional.
11. **Registry reload on startup is synchronous.** If DB is unavailable at startup, registry starts empty with a warning. Do not assume all APIs are in the registry.

---

## 8. Testing Patterns

Tests use `Blackboex.DataCase, async: true`. Build fixtures via context functions, not ExMachina. See `apps/blackboex/test/blackboex/apis/` for patterns.

```elixir
setup do
  user = user_fixture()
  {:ok, %{organization: org}} = Organizations.create_organization(user, %{name: "Test Org"})
  {:ok, api} = Apis.create_api(%{name: "Test API", organization_id: org.id, user_id: user.id})
  %{user: user, org: org, api: api}
end
```

Key testing notes:
- For publish tests, create the api with `status: "compiled"` and `source_code` set.
- Tag publish/unpublish tests with `@tag :capture_log` — Registry operations log.
- For IDOR regression: always assert `get_api(other_org.id, api.id)` returns `nil`.
- For `Keys`: `assert :crypto.hash(:sha256, plain_key) == api_key.key_hash`.
- For `MetricRollupWorker` (Oban manual mode): call `MetricRollupWorker.perform(%Oban.Job{args: %{}})` directly.

---

## 9. Gotchas for AI Agents

1. **Never `Repo.get(Api, api_id)` without `organization_id`.** Always `Apis.get_api(org_id, api_id)`.
2. **`user_id` is an integer FK.** `belongs_to :user, User, type: :id`. Using a UUID string fails with a type error.
3. **Slug auto-generation only runs on name changes.** To override, explicitly include `slug` in attrs. Changing `name` in an update does NOT regenerate slug.
4. **`publish/2` requires `compiled` status.** Returns `{:error, :not_compiled}` for `draft`.
5. **`create_version/2` is an `Ecto.Multi`.** Partial failures roll back everything.
6. **`Analytics.log_invocation/1` is fire-and-forget.** Do not check return value in tests.
7. **Registry lookups bypass GenServer.** `lookup/1` and `lookup_by_path/2` read ETS directly. Safe from any process.
8. **Dynamic modules are lost on BEAM restart.** `Registry.init/1` recompiles from `source_code`. Never clear `source_code` on a published API.
9. **`Deployer.deploy/2` runs a real smoke test.** Malformed `example_request` or a raising module returns `{:error, :smoke_test_failed}`; old module stays in registry.
10. **`start_agent_generation/3` sets `generation_status: "generating"` synchronously.** If Oban insert fails, the field is left stale. `RecoveryWorker` cleans up every 2 minutes.
11. **Dashboard metric periods.** `"24h"` = today only (hourly), not rolling. `"7d"/"30d"` = daily. `Analytics` functions use `:day`, `:week`, `:month` atoms for rolling periods — different semantics.
12. **`touch_last_used/1` debounce is client-side.** Reads `last_used_at` from the struct passed in, not from DB. Pass the freshest known struct.
