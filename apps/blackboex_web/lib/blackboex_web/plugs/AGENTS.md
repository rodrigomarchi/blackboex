# AGENTS.md — Plugs

Custom Plug middleware for the `blackboex_web` application.

## Overview

The plug stack is split across two layers:

1. **Endpoint plugs** (`BlackboexWeb.Endpoint`) — run on every single request before the router, in declaration order. This is where cross-cutting concerns live: health checks, metrics, request ID, trace context, body caching, session handling.

2. **Router pipelines** (`BlackboexWeb.Router`) — named plug pipelines composed per scope. The router selects which pipelines run based on the matched route scope.

3. **Inline plug functions** — `DynamicApiRouter` calls `RateLimiter` and `ApiAuth` as plain functions (not via `plug/2`) so it can short-circuit with structured error tuples rather than halted conns.

All custom plugs live in `BlackboexWeb.Plugs.*`.

---

## Plug Reference

### `BlackboexWeb.Plugs.HealthCheck`

**File:** `health_check.ex`

**Purpose:** Kubernetes-style liveness, readiness, and startup probes. Intercepts three specific paths and short-circuits the rest of the pipeline with `halt/1`. All other paths pass through unchanged.

**Position:** First plug in `BlackboexWeb.Endpoint` — intentionally before metrics, parsers, session, and the router so that probes remain functional even if downstream plugs crash.

**`init/1` options:** None (`opts` is passed through unchanged).

**`call/2` behavior:**

| Path | Checks | 200 when | 503 when |
|---|---|---|--|
| `/health/live` | none | always | never |
| `/health/ready` | database, ETS registry, LLM circuit breaker, Oban queue depth | all pass | any fail |
| `/health/startup` | database only | DB reachable | DB unreachable |
| any other path | — | passes through | — |

Readiness sub-checks:
- **database** — `SELECT 1` with a 5 000 ms timeout against `Blackboex.Repo`.
- **registry** — `:ets.info(:api_registry)` must not return `:undefined`.
- **circuit_breaker** — `CircuitBreaker.allow?(:anthropic)` must return `true`; reports `"open"` otherwise.
- **oban_queues** — any queue with more than 100 available jobs is reported as `"backlogged"`.

**Conn assigns added:** none.

**Error responses:** JSON body `{"status":"unavailable","checks":{...}}` with HTTP 503. Encoding errors in `respond/3` fall back to `{"status":"error"}` HTTP 500.

---

### `BlackboexWeb.Plugs.TraceContext`

**File:** `trace_context.ex`

**Purpose:** Extracts the current OpenTelemetry trace ID from the active span context and injects it into `Logger` metadata as `trace_id`. This correlates application log lines with distributed traces in any OTLP-compatible backend (Honeycomb, Jaeger, Grafana Tempo, etc.).

**Position:** Endpoint, after `Plug.RequestId` and before `Plug.Telemetry`.

**`init/1` options:** None.

**`call/2` behavior:** Reads `OpenTelemetry.Tracer.current_span_ctx()`. If a valid non-zero integer trace ID is present, sets `Logger.metadata(trace_id: <hex_string>)` (32 lower-case hex characters, zero-padded). Any exception during extraction is swallowed silently — the plug never fails a request.

**Conn assigns added:** none (side-effect is Logger metadata only).

**Error responses:** none.

---

### `BlackboexWeb.Plugs.CacheBodyReader`

**File:** `cache_body_reader.ex`

**Purpose:** Custom `body_reader` for `Plug.Parsers`. Intercepts every call to `Plug.Conn.read_body/2` and accumulates chunks into `conn.assigns[:raw_body]` as a list of binaries. Required so that webhook controllers can reconstruct the exact raw request body for HMAC signature verification after `Plug.Parsers` has already consumed the body stream.

**Position:** Endpoint, wired as the `body_reader` option of `Plug.Parsers`. Not a standalone `call/2` plug.

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  body_reader: {BlackboexWeb.Plugs.CacheBodyReader, :read_body, []},
  ...
```

**`init/1` options:** N/A — not used as a plug directly.

**`read_body/2` behavior:** Delegates to `Plug.Conn.read_body/2` for both `:ok` and `:more` returns. In both cases prepends the received chunk to `conn.assigns[:raw_body]` (or starts a new list if the key is `nil`).

**`get_raw_body/1` helper:** Reassembles the cached chunks in the correct order (`Enum.reverse/1` then `Enum.join/1`). Guards against three shapes of the assign:
- `nil` — returns `""`.
- `list` (normal case) — reverses and joins.
- `binary` (legacy/direct assign) — returns as-is.

**Conn assigns added:** `:raw_body` — list of binary chunks, or `nil` if no body was read.

**Error responses:** none.

**Gotcha:** `conn.assigns[:raw_body]` starts as `nil`, not `[]`. The `update_in` expression uses `&[body | &1 || []]` to handle the `nil` case. If you read `:raw_body` before `Plug.Parsers` runs (i.e., before body parsing), it will be `nil`. Always use `get_raw_body/1` which handles `nil` safely.

---

### `BlackboexWeb.Plugs.AuditContext`

**File:** `audit_context.ex`

**Purpose:** Injects the current authenticated user (actor ID + IP address) into ExAudit's process-level tracking data. Every Ecto changeset audited during the same process will automatically record who made the change.

**Position:** Router pipeline `:audit_context`, used in the authenticated app scope and the admin scope.

**`init/1` options:** None.

**`call/2` behavior:** Reads `conn.assigns[:current_scope]`. If the scope has a non-nil `user`, calls `Blackboex.Audit.track(actor_id: ..., ip_address: ...)`. If there is no scope or no user, passes through silently.

**Conn assigns added:** none (side-effect is ExAudit process dictionary only).

**Error responses:** none.

**Dependency:** Must run after a plug that sets `conn.assigns[:current_scope]` (i.e., after `fetch_current_scope_for_user`).

---

### `BlackboexWeb.Plugs.RequirePlatformAdmin`

**File:** `require_platform_admin.ex`

**Purpose:** Authorization gate for the `/admin` scope. Redirects any non-platform-admin user to `/dashboard` with a flash error.

**Position:** Router pipeline `:require_platform_admin`, composed after `:require_authenticated_user` in the admin scope.

**`init/1` options:** None.

**`call/2` behavior:** Pattern-matches `conn.assigns[:current_scope]` for `%{user: %{is_platform_admin: true}}`. Any other shape (including nil scope, missing user, or `is_platform_admin: false`) redirects and halts.

**Conn assigns added:** none.

**Error responses:**
- HTTP 302 redirect to `/dashboard` with `flash[:error] = "You are not authorized to access this page."`.

**Dependency:** Must run after `fetch_current_scope_for_user` and `require_authenticated_user` (which redirects unauthenticated users before this plug is reached).

---

### `BlackboexWeb.Plugs.RequireSetup`

**File:** `require_setup.ex`

**Purpose:** Gates browser traffic on first-run setup. Until `Blackboex.Settings.setup_completed?/0` returns `true`, all browser requests are redirected to `/setup`. Once setup is complete, any `/setup*` path returns HTTP 404 so the wizard cannot be re-entered.

**Position:** Last plug of the `:browser` pipeline in the router (after `:fetch_current_scope_for_user`, before `EditorBundle`).

**`init/1` options:** None.

**`call/2` behavior:**

| Setup state | Path | Result |
|---|---|---|
| completed | `/setup`, `/setup/...` | HTTP 404, halted |
| completed | anything else | pass-through |
| pending | `/setup`, `/setup/...` | pass-through (wizard reachable) |
| pending | `/api/...`, `/p/...`, `/webhook/...`, `/assets/...`, `/dev/...` | pass-through (API + assets unaffected) |
| pending | anything else | redirect to `/setup`, halted |

**Conn assigns added:** none.

**Error responses:** redirect to `/setup` (HTTP 302) or HTTP 404 with empty body.

**Dependency:** `Blackboex.Settings.setup_completed?/0` is cached via `:persistent_term` and is safe to call on every request.

---

### `BlackboexWeb.Plugs.SetOrganization`

**File:** `set_organization.ex`

**Purpose:** Loads the active organization and membership onto `conn.assigns[:current_scope]`. Multi-tenancy context is established here for every authenticated request.

**Position:** Used as a LiveView `on_mount` hook (`BlackboexWeb.Hooks.SetOrganization`) rather than directly in router pipelines. The underlying logic in this module is shared.

**`init/1` options:** None.

**`call/2` behavior:**
1. If `conn.assigns[:current_scope]` has no user, passes through unchanged.
2. Reads `organization_id` from the session.
3. If a valid org ID is in session: loads the org and verifies the user's membership. On success, updates the scope with `Scope.with_organization/3`.
4. On any failure (missing org, lost membership, nil session key): falls back to the user's first organization (via `Organizations.list_user_organizations/1`). If no orgs exist, passes through without setting an org on the scope.

**Conn assigns modified:** `:current_scope` — the scope struct gains `.organization` and `.membership` fields via `Scope.with_organization/3`.

**Error responses:** none (silent fallback to first org).

---

### `BlackboexWeb.Plugs.ApiAuth`

**File:** `api_auth.ex`

**Purpose:** Authenticates inbound requests to published dynamic APIs by verifying an API key. Not a standard `Plug` — it exposes a single public function `authenticate/3` called inline by `DynamicApiRouter`.

**`authenticate/3` signature:**
```elixir
@spec authenticate(Plug.Conn.t(), map(), map()) ::
        {:ok, Plug.Conn.t()} | {:error, :missing_key | :invalid | :revoked | :expired}
```

**Auth skip conditions (either is sufficient):**
- `metadata.requires_auth == false`
- `api.status != "published"` (drafts/compiled APIs bypass auth)

**Key extraction precedence (first match wins):**
1. `Authorization: Bearer <key>` header
2. `X-API-Key: <key>` header
3. If neither present — `{:error, :missing_key}`

Note: query-parameter auth (`?api_key=...`) is intentionally not supported.

**On successful key verification:**
- Calls `Keys.touch_last_used/1` to update `last_used_at`.
- Assigns `:api_key` to the conn.

**Conn assigns added:** `:api_key` — the `%Blackboex.Apis.ApiKey{}` struct on success. Not set on failure.

**Error responses** (returned as `{:error, reason}` tuples, translated to HTTP by `DynamicApiRouter`):

| Reason | HTTP | Body |
|---|---|---|
| `:missing_key` | 401 | `{"error":"API key required","hint":"Pass via Authorization: Bearer bb_live_... header"}` |
| `:invalid` | 401 | `{"error":"Invalid API key"}` |
| `:revoked` | 401 | `{"error":"API key has been revoked"}` |
| `:expired` | 401 | `{"error":"API key has expired"}` |

---

### `BlackboexWeb.Plugs.RateLimiter`

**File:** `rate_limiter.ex`

**Purpose:** ETS-backed sliding-window rate limiting for dynamic API requests. Like `ApiAuth`, exposes functions rather than implementing `call/2`. Called inline from `DynamicApiRouter`.

**Backend:** `BlackboexWeb.RateLimiterBackend` (ETS-based, in-process, not distributed).

**4-layer strategy for published APIs (`check_rate/2`):**

| Layer | Bucket key | Limit | Window |
|---|---|---|---|
| 1. Per IP | `"ip:<ip>"` | 100 req/min | 60 s |
| 2. Per API key | `"key:<api_key.id>"` | `api_key.rate_limit` or 60 req/min | 60 s |
| 3. Per API (global) | `"api:<api_id>"` | 1 000 req/min | 60 s |
| 4. Per endpoint | configurable (not yet wired) | — | — |

Layers are checked in order with `with/1`. The first denial short-circuits; subsequent layers are not checked.

**Draft API rate limit (`check_rate_draft/1`):**

| Bucket key | Limit | Window |
|---|---|---|
| `"draft_ip:<ip>"` | 20 req/min | 60 s |

Applied to `compiled` and non-published APIs — IP only, no API-key or global limit.

**Response headers set on allowed requests (layer 1 only):**
- `x-ratelimit-limit: 100`
- `x-ratelimit-remaining: <count>`

**Return values:**
- `{:ok, conn}` — request allowed, proceed.
- `{:error, :rate_limited, retry_after_seconds}` — denied; `DynamicApiRouter` adds `Retry-After: <n>` header and responds HTTP 429 `{"error":"Rate limit exceeded","retry_after":<n>}`.

**Telemetry:** emits `Events.emit_rate_limit_rejected/1` on every denial with `%{type: :ip | :api_key | :global | :draft, key: <value>}`.

---

### `BlackboexWeb.Plugs.DynamicApiRouter`

**File:** `dynamic_api_router.ex`

**Purpose:** Core dispatch plug for all `/api/*` requests. Resolves the target compiled module, runs the 5-step internal pipeline, executes the module in a sandbox, and logs every invocation.

**Position:** Forwarded to from the `:api` pipeline scope via `forward "/", BlackboexWeb.Plugs.DynamicApiRouter`.

**`init/1` options:** None.

**`call/2` behavior — path dispatch:**

- Expects `conn.path_info` to be `[org_slug, slug | rest]`. Any other shape returns HTTP 404.
- Doc paths (`docs`, `openapi.json`, `openapi.yaml`) are intercepted before the execution pipeline and served by `ApiDocsPlug`.

**API resolution (`resolve_api/2`):**
1. Attempts hot lookup via `Blackboex.Apis.Registry.lookup_by_path/2` (ETS GenServer).
2. On `:not_found`, falls back to `compile_from_db/2`: loads the org and API from PostgreSQL, compiles the source code via `CodeGen.Compiler`, registers the module in the Registry, and proceeds.
3. Only APIs with `status in ["compiled", "published"]` are served. Draft or archived APIs return 404.
4. If Registry is shutting down: HTTP 503.

**Internal pipeline (run in order via `with/1`):**

```
resolve → maybe_rate_limit → maybe_authenticate → maybe_check_enforcement → execute_module
```

| Step | Published APIs | Draft/Compiled APIs |
|---|---|---|
| `maybe_rate_limit` | 4-layer (`RateLimiter.check_rate/2`) | IP-only draft limit (`RateLimiter.check_rate_draft/1`) |
| `maybe_authenticate` | `ApiAuth.authenticate/3` | skipped (always `{:ok, conn}`) |

| `execute_module` | `CodeGen.Sandbox.execute_plug/3` with 30 s timeout | same |

**`execute_module` error responses:**

| Sandbox result | HTTP | Body |
|---|---|---|
| `{:ok, result_conn}` | module's response | — |
| `{:error, :timeout}` | 504 | `{"error":"API execution timed out"}` |
| `{:error, :memory_exceeded}` | 503 | `{"error":"API execution exceeded memory limit"}` |
| `{:error, {:exception, msg}}` | 500 | `{"error":"API execution failed","detail":"<sanitized>"}` |
| `{:error, {:runtime, reason}}` | 500 | `{"error":"API execution failed","detail":"<sanitized>"}` |

Error sanitization: strips `Elixir.` prefixes and `Blackboex.DynamicApi.Api_<hash>.` module paths, truncates to 500 characters.

**Post-execution side effects (always run, even on pipeline errors):**
1. `Telemetry.Events.emit_api_request/1` — duration + status code metrics.
2. `Analytics.log_invocation/1` — writes an `InvocationLog` row with method, path, status, duration, body sizes, IP, and optional error message.
**Conn assigns added:** `:api_key` (set by `ApiAuth`, used for invocation log).

---

### `BlackboexWeb.Plugs.ApiDocsPlug`

**File:** `api_docs_plug.ex`

**Purpose:** Serves OpenAPI documentation for published APIs. Exposes three helper functions called directly by `DynamicApiRouter` — not a `call/2` plug.

**Functions:**

| Function | Path suffix | Content-Type | Description |
|---|---|---|---|
| `serve_spec_json/4` | `openapi.json` | `application/json` | OpenAPI 3.x spec as JSON |
| `serve_spec_yaml/4` | `openapi.yaml` | `text/yaml` | OpenAPI 3.x spec as YAML |
| `serve_swagger_ui/4` | `docs` | `text/html` | Swagger UI page (CDN assets from unpkg.com) |

The Swagger UI embeds a hard-coded spec URL of `/api/<org_slug>/<api_slug>/openapi.json`. The base URL for the spec is built from `conn.scheme`, `conn.host`, and `conn.port`.

The `title` attribute in the Swagger UI HTML is escaped with a minimal HTML escaper (`&`, `<`, `>`, `"`) to prevent XSS.

**Conn assigns added:** none (all functions call `halt/1` after sending).

---

## Plug Composition Order

### Endpoint (`BlackboexWeb.Endpoint`) — every request

```
1.  BlackboexWeb.Plugs.HealthCheck          ← short-circuits /health/* paths
2.  PromEx.Plug                              ← Prometheus /metrics scrape endpoint
3.  Plug.Static                              ← static file serving
4.  [dev only] Phoenix.LiveReloader         ← code hot-reload
5.  [dev only] Phoenix.CodeReloader
6.  [dev only] Phoenix.Ecto.CheckRepoStatus
7.  Phoenix.LiveDashboard.RequestLogger
8.  Plug.RequestId                           ← injects X-Request-Id
9.  BlackboexWeb.Plugs.TraceContext          ← injects trace_id into Logger metadata
10. Plug.Telemetry                           ← emits [:phoenix, :endpoint] events
11. Plug.Parsers (+ CacheBodyReader)         ← parses body; raw body cached in :raw_body
12. Plug.MethodOverride
13. Plug.Head
14. Plug.Session                             ← cookie-based session
15. BlackboexWeb.Router                      ← routes to pipeline + controller/live
```

### Router pipelines

See `router.ex` for pipeline definitions.

---

## How to Add a New Plug

1. Create `apps/blackboex_web/lib/blackboex_web/plugs/<name>.ex` implementing `@behaviour Plug` with `init/1` and `call/2`. Add `@spec` on every public function.
2. Wire it in: endpoint (every request), a `pipeline` block in `Router`, a `pipe_through` list, or inline in `DynamicApiRouter.run_pipeline/5` for structured `{:ok}/{:error}` returns.
3. Order matters: plugs that set assigns must precede plugs that read them (`fetch_current_scope_for_user` before `AuditContext`/`RequirePlatformAdmin`; `TraceContext` after `Plug.RequestId`).
4. Write tests in `test/blackboex_web/plugs/<name>_test.exs` using `BlackboexWeb.ConnCase`.
5. Run `make lint` — Dialyzer and Credo must be clean before merging.

---

## Gotchas

### CacheBodyReader nil guard

`conn.assigns[:raw_body]` is `nil` before `Plug.Parsers` runs and after requests with no body. Always use the provided `get_raw_body/1` helper — it handles `nil`, list, and binary shapes:

```elixir
# WRONG — crashes on nil
conn.assigns.raw_body |> Enum.join()

# CORRECT
BlackboexWeb.Plugs.CacheBodyReader.get_raw_body(conn)
```

The internal accumulator expression `&[body | &1 || []]` exploits the fact that `nil || []` evaluates to `[]`, prepending the new chunk to an empty list on the first call.

### `fetch_query_params` must be called before reading query params

`DynamicApiRouter` does not call `fetch_query_params/1`. If a sandboxed user module or any plug downstream needs to read `conn.query_params`, it must call `Plug.Conn.fetch_query_params/1` itself. Accessing `conn.query_params` before fetching raises `Plug.Conn.unfetched_error`.

### Remote IP behind a reverse proxy

`conn.remote_ip` is set by Cowboy/Bandit based on the TCP connection source. Behind nginx, a load balancer, or a Kubernetes ingress, this will be the proxy IP — not the end-user's IP. This affects:
- `RateLimiter` — all requests appear to come from the proxy; rate limiting is effectively per-proxy not per-client.
- `AuditContext` — audit logs record the proxy IP.

The endpoint has a comment describing two options to fix this (the `remote_ip` Hex package or an `X-Forwarded-For` plug). Neither is currently wired in — add `RemoteIp` before `TraceContext` in the endpoint if deploying behind a proxy in production.

### Webhook body must not be re-read

`Plug.Parsers` consumes the request body stream. `WebhookController` must call `CacheBodyReader.get_raw_body(conn)` to get the raw bytes — attempting to call `Plug.Conn.read_body/2` again returns `""`. Never mark a webhook as processed before both verifying the signature and completing the handler logic (check → process → mark).

### ApiAuth is not a Plug module

`BlackboexWeb.Plugs.ApiAuth` does not implement the `Plug` behaviour and has no `call/2`. It cannot be used with `plug BlackboexWeb.Plugs.ApiAuth` in a pipeline. Use it only by calling `ApiAuth.authenticate(conn, api, metadata)` directly.

### Rate limiter Layer 2 runs before auth

Layer 2 checks `conn.assigns[:api_key]`. Because `RateLimiter.check_rate/2` is called before `ApiAuth.authenticate/3` in `DynamicApiRouter.run_pipeline/5`, the `:api_key` assign is always `nil` during rate limiting. Layer 2 is effectively a no-op on the first pass. If you reorder rate limiting and auth, Layer 2 will begin enforcing per-key limits.
