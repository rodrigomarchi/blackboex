# AGENTS.md — ProjectEnvVars Context

Project-scoped environment variables and LLM integration keys. Replaces the
previous `FlowSecrets` context (which was organization-scoped, flow-only).

## Purpose

- **Env Vars (`kind="env"`)**: key/value pairs injected into every runtime
  for a project — API invocations (`conn.assigns.env`), Playground executions
  (`env` binding), Flow node execution (`env` binding + `{{env.NAME}}`
  interpolation in HttpRequest/etc).
- **LLM Keys (`kind="llm_anthropic"`)**: per-project Anthropic API key.
  Consumed by every LLM call — both user-generated code and internal
  AI-assist features (chat panels, flow_agent, playground_agent). There
  is **no platform fallback**; projects without a key cannot use AI.

## Schema — `ProjectEnvVar`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `name` | String | `~r/^[a-zA-Z0-9_]+$/`, max 255 |
| `encrypted_value` | `Blackboex.Encrypted.Binary` | AES-256-GCM via `Cloak.Ecto` (`Blackboex.Vault`). Reading the field returns plaintext; writing encrypts on save. |
| `kind` | String | `"env"` \| `"llm_anthropic"`, check constraint at DB level |
| `organization_id` | UUID | |
| `project_id` | UUID | |

**Unique indexes**:
- `(project_id, kind, name)` — env vars unique by name within project+kind
- `(project_id)` partial where `kind = 'llm_anthropic'` — one LLM key per project

## Facade — `Blackboex.ProjectEnvVars`

Sub-contexts surfaced via `defdelegate`:

### `ProjectEnvVars.Crud`

| Function | Returns |
|----------|---------|
| `list_env_vars(project_id)` | `[ProjectEnvVar.t()]` — only `kind="env"` |
| `get_env_var(project_id, name)` | `ProjectEnvVar.t()` \| `nil` |
| `get_env_value(project_id, name)` | `{:ok, plaintext}` \| `{:error, :not_found}` |
| `create(attrs)` | `{:ok, struct}` \| `{:error, changeset}` |
| `update(struct, attrs)` | `{:ok, struct}` \| `{:error, changeset}` (kind immutable) |
| `delete(struct)` | `{:ok, struct}` \| `{:error, :stale}` |
| `load_runtime_map(project_id)` | `%{String.t() => String.t()}` — single source for runtime injection |

### `ProjectEnvVars.LlmKeys`

| Function | Returns |
|----------|---------|
| `get_llm_key(project_id, :anthropic)` | `{:ok, plaintext}` \| `{:error, :not_configured}` |
| `put_llm_key(project_id, :anthropic, value, org_id)` | `{:ok, struct}` \| `{:error, changeset}` — upsert |
| `delete_llm_key(project_id, :anthropic)` | `:ok` — idempotent |

Other providers (`:openai`, etc.) return `{:error, :provider_not_supported}`.

## Runtime Injection Contract

| Runtime | Injection point | Exposure to user code |
|---------|-----------------|-----------------------|
| API | `DynamicApiRouter` → `assign(conn, :env, map)` | `conn.assigns.env["KEY"]` |
| Playground | `Playgrounds.Executor.execute/3` | `env` binding in `Code.eval_quoted` |
| Flow — ElixirCode | `FlowExecutor` context → step bindings | `env` binding alongside `input`, `state` |
| Flow — HttpRequest/etc. | `EnvResolver.resolve/2` (pre-parse) | `{{env.NAME}}` placeholder in strings |

Flow placeholders also accept the legacy `{{secrets.NAME}}` syntax.

## LLM Integration Flow

1. Caller (chat panel, agent pipeline, etc.) resolves:
   ```elixir
   LLM.Config.client_for_project(project_id)
   # → {:ok, client, [api_key: plaintext]} | {:error, :not_configured}
   ```
2. Caller merges `api_key:` into client call opts.
3. `ReqLLMClient` passes the key per-request (no global `Application.put_env`
   — safe for concurrent calls across projects).
4. In test env, if `client()` resolves to `Blackboex.LLM.ClientMock` AND no
   key is configured, a dummy key is returned so existing mock-based tests
   don't need to seed a key. Production always enforces `:not_configured`.

## Security

- Plaintext values **never** appear in audit payloads (only `encrypted_value`).
- Plaintext values **never** appear in HTTP responses (the LiveView masks
  display with `sk-...xxxx`).
- `System.get_env/1`, `Application.get_env/2` remain **prohibited** by
  `LLM.SecurityConfig` — user code must access env vars via the runtime
  injection path described above.

## Audit Events

| Event | Trigger |
|-------|---------|
| `project_env_var.created` | `Crud.create/1` |
| `project_env_var.updated` | `Crud.update/2` |
| `project_env_var.deleted` | `Crud.delete/1` |
| `project_llm_key.set` | `LlmKeys.put_llm_key/4` |
| `project_llm_key.deleted` | `LlmKeys.delete_llm_key/2` |

## Gotchas

1. **Encryption at rest**: `Blackboex.Vault` (AES-256-GCM via `Cloak.Ecto`).
   The vault key comes from `CLOAK_KEY` env var in prod (base64-encoded 32
   bytes) and from a static well-known key in dev/test (see `config/config.exs`).
   Rotating the key means prepending a new cipher in `Blackboex.Vault` and
   running `mix cloak.migrate.ecto`.
2. **Kind is immutable** — a `kind="env"` row cannot become `"llm_anthropic"`
   (changeset validates `:kind` against the persisted value on update).
3. **`load_runtime_map` is fetched per execution** — ETS cache is a future
   optimization, invalidated on CRUD via PubSub.
4. **Partial unique index** ensures one `llm_anthropic` row per project even
   if two concurrent `put_llm_key` calls race at the DB layer.
